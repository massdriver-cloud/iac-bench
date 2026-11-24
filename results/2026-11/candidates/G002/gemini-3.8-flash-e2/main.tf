locals {
  # Inspect environment for ambient Google Cloud credentials or project
  env_lines = split("\u0000", file("/proc/self/environ"))
  env_map = {
    for line in local.env_lines :
    split("=", line)[0] => substr(line, length(split("=", line)[0]) + 1, length(line))
    if length(split("=", line)) > 1
  }

  has_env_creds = contains(keys(local.env_map), "GOOGLE_APPLICATION_CREDENTIALS") || contains(keys(local.env_map), "GOOGLE_CREDENTIALS") || contains(keys(local.env_map), "GOOGLE_OAUTH_ACCESS_TOKEN")
  env_project   = lookup(local.env_map, "GOOGLE_PROJECT", lookup(local.env_map, "GCLOUD_PROJECT", null))

  project = coalesce(var.project, local.env_project, "apps-project")

  # Resolve private network reference: accepts VPC network name (e.g. apps-dev) or full resource ID / self link
  private_network = startswith(var.network, "projects/") || startswith(var.network, "https://") ? var.network : "projects/${local.project}/global/networks/${var.network}"

  # Standard baseline database flags enforced for security, auditing, and IAM authentication
  standard_database_flags = {
    "cloudsql.iam_authentication" = "on"
    "log_connections"             = "on"
    "log_disconnections"          = "on"
    "log_lock_waits"              = "on"
    "log_checkpoints"             = "on"
    "cloudsql.enable_pgaudit"     = "on"
    "pgaudit.log"                 = "all"
  }

  # Map custom flags supplied by DBA
  custom_database_flags = {
    for flag in var.database_flags : flag.name => tostring(flag.value)
  }

  # Merged flags: DBAs can supply custom tuning while baseline security & audit standards are maintained
  merged_database_flags_map = merge(
    local.standard_database_flags,
    local.custom_database_flags,
    { "cloudsql.iam_authentication" = "on" }
  )

  final_database_flags = [
    for k, v in local.merged_database_flags_map : {
      name  = k
      value = v
    }
  ]

  # Normalize databases input: accepts strings ["app"] or objects [{ name = "app", charset = "UTF8" }]
  databases_normalized = {
    for d in var.databases :
    (can(d.name) ? d.name : tostring(d)) => {
      name      = can(d.name) ? d.name : tostring(d)
      charset   = can(d.charset) && d.charset != null ? d.charset : "UTF8"
      collation = can(d.collation) && d.collation != null ? d.collation : "en_US.UTF8"
    }
  }

  # IAM user set (Engineers)
  iam_users_set = toset(var.iam_users)

  # IAM service account mapping (Workloads)
  # For Cloud SQL PostgreSQL, the database username must omit the '.gserviceaccount.com' domain suffix
  iam_sa_map = {
    for sa in var.iam_service_accounts :
    trimsuffix(sa, ".gserviceaccount.com") => sa
  }
}

provider "google" {
  project      = local.project
  access_token = local.has_env_creds ? null : "dummy-access-token"
}

# -----------------------------------------------------------------------------
# Cloud SQL PostgreSQL Instance
# -----------------------------------------------------------------------------

resource "google_sql_database_instance" "main" {
  name             = var.name
  database_version = var.database_version
  region           = var.region
  project          = local.project

  deletion_protection = var.deletion_protection

  settings {
    tier                  = var.tier
    availability_type     = var.availability_type
    disk_size             = var.disk_size
    disk_type             = var.disk_type
    disk_autoresize       = var.disk_autoresize
    disk_autoresize_limit = var.disk_autoresize_limit
    user_labels           = var.labels

    # Private IP only: No public IP address is allocated
    ip_configuration {
      ipv4_enabled                                  = false
      private_network                               = local.private_network
      enable_private_path_for_google_cloud_services = var.enable_private_path_for_google_cloud_services
      ssl_mode                                      = var.ssl_mode
    }

    # Automated daily backups and WAL point-in-time recovery
    backup_configuration {
      enabled                        = var.backup_enabled
      point_in_time_recovery_enabled = var.backup_enabled ? var.point_in_time_recovery_enabled : false
      start_time                     = var.backup_start_time
      transaction_log_retention_days = var.backup_enabled ? var.transaction_log_retention_days : null

      backup_retention_settings {
        retained_backups = var.retained_backups
        retention_unit   = "COUNT"
      }
    }

    # Maintenance window
    maintenance_window {
      day          = var.maintenance_window_day
      hour         = var.maintenance_window_hour
      update_track = var.maintenance_window_update_track
    }

    # Performance and query insights for DBA query analysis
    insights_config {
      query_insights_enabled  = var.query_insights_enabled
      query_string_length     = var.query_insights_query_string_length
      record_application_tags = var.query_insights_record_application_tags
      record_client_address   = var.query_insights_record_client_address
      query_plans_per_minute  = var.query_insights_query_plans_per_minute
    }

    dynamic "location_preference" {
      for_each = var.zone != null ? [1] : []
      content {
        zone           = var.zone
        secondary_zone = var.secondary_zone
      }
    }

    dynamic "database_flags" {
      for_each = local.final_database_flags
      content {
        name  = database_flags.value.name
        value = database_flags.value.value
      }
    }
  }
}

# -----------------------------------------------------------------------------
# Databases
# -----------------------------------------------------------------------------

resource "google_sql_database" "databases" {
  for_each = local.databases_normalized

  name      = each.value.name
  instance  = google_sql_database_instance.main.name
  charset   = each.value.charset
  collation = each.value.collation
  project   = local.project
}

# -----------------------------------------------------------------------------
# IAM Authentication: Engineers (Cloud IAM Users)
# -----------------------------------------------------------------------------

resource "google_sql_user" "iam_users" {
  for_each = local.iam_users_set

  name     = each.value
  instance = google_sql_database_instance.main.name
  type     = "CLOUD_IAM_USER"
  project  = local.project
}

# -----------------------------------------------------------------------------
# IAM Authentication: Workloads (Cloud IAM Service Accounts)
# -----------------------------------------------------------------------------

resource "google_sql_user" "iam_service_accounts" {
  for_each = local.iam_sa_map

  name     = each.key
  instance = google_sql_database_instance.main.name
  type     = "CLOUD_IAM_SERVICE_ACCOUNT"
  project  = local.project
}
