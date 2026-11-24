locals {
  net_matches       = regexall("projects/([^/]+)/global/networks/", var.vpc_network)
  extracted_project = length(local.net_matches) > 0 ? local.net_matches[0][0] : null
  effective_project = coalesce(var.project, local.extracted_project, "default-project")

  # Ensure the private network ID matches the required Google Cloud resource link format
  private_network_id = (
    can(regex("^projects/", var.vpc_network)) || can(regex("^https?://", var.vpc_network))
    ? var.vpc_network
    : "projects/${local.effective_project}/global/networks/${var.vpc_network}"
  )

  # Baseline database flags for security auditing and operational excellence
  default_database_flags = {
    "cloudsql.iam_authentication" = "on"
    "log_connections"             = "on"
    "log_disconnections"          = "on"
    "log_lock_waits"              = "on"
    "log_checkpoints"             = "on"
  }

  user_database_flags = try(
    { for f in var.database_flags : f.name => tostring(f.value) },
    { for k, v in var.database_flags : tostring(k) => tostring(v) }
  )

  # Merge default baseline flags with DBA-specified flags; IAM authentication is always enforced
  merged_database_flags = merge(
    local.default_database_flags,
    local.user_database_flags,
    {
      "cloudsql.iam_authentication" = "on"
    }
  )

  # Normalize databases input into a consistent map
  databases_map = {
    for item in var.databases :
    (try(item.name, item)) => {
      name      = try(item.name, item)
      charset   = try(item.charset, "UTF8")
      collation = try(item.collation, "en_US.UTF8")
    }
  }

  default_labels = {
    managed_by = "opentofu"
    db_engine  = "postgresql"
    team       = "dba"
  }

  merged_labels = merge(local.default_labels, var.labels)
}

resource "google_sql_database_instance" "instance" {
  name             = var.instance_name
  database_version = var.database_version
  region           = var.region
  project          = local.effective_project

  settings {
    tier                  = var.tier
    availability_type     = var.availability_type
    disk_size             = var.disk_size
    disk_type             = var.disk_type
    disk_autoresize       = var.disk_autoresize
    disk_autoresize_limit = var.disk_autoresize_limit
    user_labels           = local.merged_labels

    ip_configuration {
      ipv4_enabled                                  = false
      private_network                               = local.private_network_id
      enable_private_path_for_google_cloud_services = true
      ssl_mode                                      = "ENCRYPTED_ONLY"
    }

    backup_configuration {
      enabled                        = true
      point_in_time_recovery_enabled = true
      start_time                     = var.backup_start_time
      transaction_log_retention_days = var.transaction_log_retention_days
      backup_retention_settings {
        retained_backups = var.backup_retention_count
        retention_unit   = "COUNT"
      }
    }

    insights_config {
      query_insights_enabled  = var.query_insights_enabled
      query_string_length     = 1024
      record_application_tags = true
      record_client_address   = true
    }

    dynamic "database_flags" {
      for_each = local.merged_database_flags
      content {
        name  = database_flags.key
        value = database_flags.value
      }
    }

    maintenance_window {
      day          = var.maintenance_window_day
      hour         = var.maintenance_window_hour
      update_track = var.maintenance_window_update_track
    }

    dynamic "location_preference" {
      for_each = var.zone != null || var.secondary_zone != null ? [1] : []
      content {
        zone           = var.zone
        secondary_zone = var.secondary_zone
      }
    }
  }

  deletion_protection = var.deletion_protection
}

resource "google_sql_database" "databases" {
  for_each = local.databases_map

  name      = each.value.name
  instance  = google_sql_database_instance.instance.name
  project   = local.effective_project
  charset   = each.value.charset
  collation = each.value.collation
}

# IAM user accounts for engineers (audited by Google identity)
resource "google_sql_user" "iam_users" {
  for_each = var.iam_users

  name     = each.value
  instance = google_sql_database_instance.instance.name
  project  = local.effective_project
  type     = "CLOUD_IAM_USER"
}

# IAM service accounts for workloads running on GKE and Compute Engine
resource "google_sql_user" "iam_service_accounts" {
  for_each = var.iam_service_accounts

  name     = trimsuffix(each.value, ".gserviceaccount.com")
  instance = google_sql_database_instance.instance.name
  project  = local.effective_project
  type     = "CLOUD_IAM_SERVICE_ACCOUNT"
}

# Optional additional / built-in users
resource "google_sql_user" "additional_users" {
  for_each = { for u in var.additional_users : u.name => u }

  name     = each.value.name
  instance = google_sql_database_instance.instance.name
  project  = local.effective_project
  password = each.value.password
  type     = each.value.type
}
