data "google_client_config" "current" {}

locals {
  project_id = coalesce(var.project_id, data.google_client_config.current.project)
  region     = coalesce(var.region, try(nullif(data.google_client_config.current.region, ""), null), "us-central1")

  # Resolve network resource URI for Private Services Access
  private_network = (
    can(regex("^projects/", var.network)) || can(regex("^https://", var.network))
    ? var.network
    : "projects/${local.project_id}/global/networks/${var.network}"
  )

  # Standard baseline flags: IAM authentication, pgAudit auditing, and connection logging
  default_database_flags = {
    # Identity & Access Management: enforce Google identity database authentication
    "cloudsql.iam_authentication" = "on"

    # Auditing: enable pgAudit extension to audit database activities
    "cloudsql.enable_pgaudit" = "on"
    "pgaudit.log"             = "ddl,role"

    # Connection logging for security audit trails
    "log_connections"    = "on"
    "log_disconnections" = "on"

    # Diagnostics and performance monitoring
    "log_lock_waits"  = "on"
    "log_checkpoints" = "on"
    "log_temp_files"  = "0"
  }

  # DBA custom flags merge with baseline flags (DBA settings take precedence)
  all_database_flags = merge(local.default_database_flags, var.database_flags)

  # Normalize databases input to support either string list or object list
  databases_map = {
    for db in var.databases :
    (can(tostring(db)) ? tostring(db) : db.name) => {
      name      = can(tostring(db)) ? tostring(db) : db.name
      charset   = try(db.charset, "UTF8")
      collation = try(db.collation, "en_US.UTF8")
    }
  }

  labels = merge(
    {
      "managed-by" = "opentofu"
    },
    var.labels
  )
}

resource "google_sql_database_instance" "primary" {
  name                = var.name
  database_version    = var.database_version
  region              = local.region
  project             = local.project_id
  deletion_protection = var.deletion_protection

  settings {
    tier                  = var.tier
    edition               = var.edition
    availability_type     = var.availability_type
    disk_size             = var.disk_size
    disk_type             = var.disk_type
    disk_autoresize       = var.disk_autoresize
    disk_autoresize_limit = var.disk_autoresize_limit

    dynamic "location_preference" {
      for_each = var.zone != null || var.secondary_zone != null ? [1] : []
      content {
        zone           = var.zone
        secondary_zone = var.secondary_zone
      }
    }

    ip_configuration {
      ipv4_enabled                                  = false
      private_network                               = local.private_network
      ssl_mode                                      = var.ssl_mode
      enable_private_path_for_google_cloud_services = var.enable_private_path_for_google_cloud_services
      allocated_ip_range                            = var.allocated_ip_range
    }

    backup_configuration {
      enabled                        = true
      start_time                     = var.backup_start_time
      point_in_time_recovery_enabled = true
      transaction_log_retention_days = var.transaction_log_retention_days

      backup_retention_settings {
        retained_backups = var.retained_backups
        retention_unit   = "COUNT"
      }
    }

    maintenance_window {
      day          = var.maintenance_window_day
      hour         = var.maintenance_window_hour
      update_track = var.maintenance_window_update_track
    }

    insights_config {
      query_insights_enabled  = var.insights_config.query_insights_enabled
      query_string_length     = var.insights_config.query_string_length
      record_application_tags = var.insights_config.record_application_tags
      record_client_address   = var.insights_config.record_client_address
      query_plans_per_minute  = var.insights_config.query_plans_per_minute
    }

    dynamic "database_flags" {
      for_each = local.all_database_flags
      content {
        name  = database_flags.key
        value = database_flags.value
      }
    }

    user_labels = local.labels
  }
}

resource "google_sql_database" "databases" {
  for_each = local.databases_map

  name      = each.value.name
  instance  = google_sql_database_instance.primary.name
  project   = local.project_id
  charset   = each.value.charset
  collation = each.value.collation
}

# Engineer identities audited by security team
resource "google_sql_user" "iam_users" {
  for_each = toset(var.iam_users)

  name     = each.value
  instance = google_sql_database_instance.primary.name
  project  = local.project_id
  type     = "CLOUD_IAM_USER"
}

# Workload identities (GKE pods / Compute Engine VMs) audited by security team
# In Cloud SQL PostgreSQL, service account usernames strip the .gserviceaccount.com suffix
resource "google_sql_user" "iam_service_accounts" {
  for_each = toset(var.iam_service_accounts)

  name     = trimsuffix(each.value, ".gserviceaccount.com")
  instance = google_sql_database_instance.primary.name
  project  = local.project_id
  type     = "CLOUD_IAM_SERVICE_ACCOUNT"
}

# Group identities audited by security team
resource "google_sql_user" "iam_groups" {
  for_each = toset(var.iam_groups)

  name     = each.value
  instance = google_sql_database_instance.primary.name
  project  = local.project_id
  type     = "CLOUD_IAM_GROUP"
}

# Optional traditional built-in SQL users
resource "google_sql_user" "additional_users" {
  for_each = { for u in var.additional_users : u.name => u }

  name     = each.value.name
  instance = google_sql_database_instance.primary.name
  project  = local.project_id
  password = each.value.password
  type     = "BUILT_IN"
}

# Optional read replicas configured by DBAs
resource "google_sql_database_instance" "replicas" {
  for_each = var.read_replicas

  name                 = "${var.name}-replica-${each.key}"
  database_version     = var.database_version
  region               = coalesce(each.value.region, local.region)
  project              = local.project_id
  master_instance_name = google_sql_database_instance.primary.name
  deletion_protection  = var.deletion_protection

  settings {
    tier            = coalesce(each.value.tier, var.tier)
    disk_size       = coalesce(each.value.disk_size, var.disk_size)
    disk_type       = each.value.disk_type
    disk_autoresize = each.value.disk_autoresize

    dynamic "location_preference" {
      for_each = each.value.zone != null ? [1] : []
      content {
        zone = each.value.zone
      }
    }

    ip_configuration {
      ipv4_enabled                                  = false
      private_network                               = local.private_network
      ssl_mode                                      = var.ssl_mode
      enable_private_path_for_google_cloud_services = var.enable_private_path_for_google_cloud_services
      allocated_ip_range                            = var.allocated_ip_range
    }

    insights_config {
      query_insights_enabled  = var.insights_config.query_insights_enabled
      query_string_length     = var.insights_config.query_string_length
      record_application_tags = var.insights_config.record_application_tags
      record_client_address   = var.insights_config.record_client_address
      query_plans_per_minute  = var.insights_config.query_plans_per_minute
    }

    dynamic "database_flags" {
      for_each = merge(local.default_database_flags, each.value.database_flags)
      content {
        name  = database_flags.key
        value = database_flags.value
      }
    }

    user_labels = local.labels
  }
}
