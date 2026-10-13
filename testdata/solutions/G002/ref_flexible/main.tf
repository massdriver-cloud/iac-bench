# Authentication is IAM-only: no built-in passwords are created or accepted.
data "google_client_config" "current" {}

resource "google_sql_database_instance" "this" {
  name                = var.instance_name
  database_version    = var.database_version
  deletion_protection = var.deletion_protection

  settings {
    tier                  = var.tier
    edition               = "ENTERPRISE"
    availability_type     = var.high_availability ? "REGIONAL" : "ZONAL"
    disk_type             = "PD_SSD"
    disk_size             = var.disk_size_gb
    disk_autoresize       = true
    disk_autoresize_limit = var.disk_autoresize_limit_gb
    user_labels           = merge(var.labels, { managed-by = "opentofu" })

    ip_configuration {
      ipv4_enabled    = false
      private_network = "projects/${data.google_client_config.current.project}/global/networks/${var.network}"
      ssl_mode        = "TRUSTED_CLIENT_CERTIFICATE_REQUIRED"
    }

    backup_configuration {
      enabled                        = var.backup.enabled
      point_in_time_recovery_enabled = var.backup.enabled
      start_time                     = var.backup.start_time
      transaction_log_retention_days = var.backup.log_retention_days

      backup_retention_settings {
        retained_backups = var.backup.retained_backups
      }
    }

    maintenance_window {
      day  = var.maintenance_day
      hour = var.maintenance_hour
    }

    dynamic "database_flags" {
      for_each = merge({ "cloudsql.iam_authentication" = "on" }, var.database_flags)
      content {
        name  = database_flags.key
        value = database_flags.value
      }
    }
  }
}

resource "google_sql_user" "iam" {
  for_each = var.iam_users

  name     = each.value
  instance = google_sql_database_instance.this.name
  type     = "CLOUD_IAM_USER"
}
