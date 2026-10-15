locals {
  labels = merge(var.labels, { managed-by = "opentofu" })
}

# Authentication is IAM-only: no built-in passwords are created or accepted.
# Identity login and connection logging are applied after the flags input, so
# no input can turn them off.
data "google_client_config" "current" {}

resource "google_sql_database_instance" "this" {
  name                = var.instance_name
  database_version    = var.database_version
  deletion_protection = var.deletion_protection
  # Customer-managed key, if policy requires one; it can only be set at creation.
  encryption_key_name = var.kms_key_name

  settings {
    tier                  = var.tier
    edition               = "ENTERPRISE"
    availability_type     = var.high_availability ? "REGIONAL" : "ZONAL"
    disk_type             = "PD_SSD"
    disk_size             = var.disk_size_gb
    disk_autoresize       = true
    disk_autoresize_limit = var.disk_autoresize_limit_gb
    # Cloud SQL instances do not inherit the provider's default_labels.
    user_labels = local.labels
    # Backups outlive the instance, so retiring one never loses its history.
    retain_backups_on_delete = true

    ip_configuration {
      ipv4_enabled    = false
      private_network = "projects/${data.google_client_config.current.project}/global/networks/${var.network}"
      ssl_mode        = var.ssl_mode
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

    insights_config {
      query_insights_enabled = true
    }

    dynamic "database_flags" {
      for_each = merge(var.database_flags, {
        "cloudsql.iam_authentication" = "on"
        log_connections               = "on"
        log_disconnections            = "on"
      })
      content {
        name  = database_flags.key
        value = database_flags.value
      }
    }
  }
}

resource "google_sql_database" "this" {
  for_each = var.databases

  name     = each.value
  instance = google_sql_database_instance.this.name
  # Removing a name from var.databases keeps the data while the instance is
  # protected; turn deletion protection off to drop it for real.
  deletion_policy = var.deletion_protection ? "ABANDON" : "DELETE"
}
