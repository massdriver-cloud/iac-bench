locals {
  is_prod = var.environment == "prod"

  network_project_id = coalesce(var.network_project_id, var.project_id)
  network_name       = coalesce(var.network_name, "apps-${var.environment}")
  network_self_link  = "projects/${local.network_project_id}/global/networks/${local.network_name}"

  availability_type = coalesce(var.availability_type, local.is_prod ? "REGIONAL" : "ZONAL")
  retained_backups  = coalesce(var.retained_backups, local.is_prod ? 30 : 7)

  # Flags that are the same on every instance and cannot be overridden by callers.
  enforced_database_flags = {
    "cloudsql.iam_authentication" = "on"
    "log_connections"             = "on"
    "log_disconnections"          = "on"
    "log_checkpoints"             = "on"
    "log_lock_waits"              = "on"
    "log_temp_files"              = "0"
  }

  database_flags = merge(var.database_flags, local.enforced_database_flags)

  labels = merge(
    var.labels,
    {
      environment = var.environment
      managed-by  = "opentofu"
      engine      = "postgresql"
    }
  )

  # Cloud SQL expects service-account IAM users without the .gserviceaccount.com suffix.
  iam_users = {
    for p in var.iam_principals : p => {
      is_service_account = endswith(p, ".gserviceaccount.com")
      name               = endswith(p, ".gserviceaccount.com") ? trimsuffix(p, ".gserviceaccount.com") : p
    }
  }
}

resource "google_sql_database_instance" "this" {
  project          = var.project_id
  name             = var.name
  region           = var.region
  database_version = var.database_version

  deletion_protection = var.deletion_protection

  settings {
    edition           = var.edition
    tier              = var.tier
    availability_type = local.availability_type

    disk_type             = var.disk_type
    disk_size             = var.disk_size_gb
    disk_autoresize       = true
    disk_autoresize_limit = var.disk_autoresize_limit_gb

    deletion_protection_enabled = var.deletion_protection
    user_labels                 = local.labels

    ip_configuration {
      ipv4_enabled                                  = false
      private_network                               = local.network_self_link
      allocated_ip_range                            = var.allocated_ip_range
      enable_private_path_for_google_cloud_services = var.enable_private_path_for_google_cloud_services
      ssl_mode                                      = var.require_client_certificates ? "TRUSTED_CLIENT_CERTIFICATE_REQUIRED" : "ENCRYPTED_ONLY"
    }

    backup_configuration {
      enabled                        = true
      start_time                     = var.backup_start_time
      point_in_time_recovery_enabled = true
      transaction_log_retention_days = var.transaction_log_retention_days

      backup_retention_settings {
        retained_backups = local.retained_backups
        retention_unit   = "COUNT"
      }
    }

    maintenance_window {
      day          = var.maintenance_window_day
      hour         = var.maintenance_window_hour
      update_track = var.maintenance_update_track
    }

    dynamic "deny_maintenance_period" {
      for_each = var.deny_maintenance_periods
      content {
        start_date = deny_maintenance_period.value.start_date
        end_date   = deny_maintenance_period.value.end_date
        time       = deny_maintenance_period.value.time
      }
    }

    insights_config {
      query_insights_enabled  = var.query_insights_enabled
      query_plans_per_minute  = var.query_insights_enabled ? 5 : null
      query_string_length     = var.query_insights_enabled ? 1024 : null
      record_application_tags = var.query_insights_enabled
      record_client_address   = var.query_insights_enabled
    }

    dynamic "data_cache_config" {
      for_each = var.edition == "ENTERPRISE_PLUS" ? [1] : []
      content {
        data_cache_enabled = var.data_cache_enabled
      }
    }

    dynamic "database_flags" {
      for_each = local.database_flags
      content {
        name  = database_flags.key
        value = database_flags.value
      }
    }
  }

  lifecycle {
    # Disk grows automatically; never shrink it back to the declared starting size.
    ignore_changes = [settings[0].disk_size]

    precondition {
      condition     = var.edition == "ENTERPRISE_PLUS" || !var.data_cache_enabled
      error_message = "data_cache_enabled requires edition = ENTERPRISE_PLUS."
    }
  }
}

resource "google_sql_database" "this" {
  for_each = var.databases

  project   = var.project_id
  instance  = google_sql_database_instance.this.name
  name      = each.key
  charset   = each.value.charset
  collation = each.value.collation
}

resource "google_sql_user" "iam" {
  for_each = local.iam_users

  project  = var.project_id
  instance = google_sql_database_instance.this.name
  name     = each.value.name
  type     = each.value.is_service_account ? "CLOUD_IAM_SERVICE_ACCOUNT" : "CLOUD_IAM_USER"
}
