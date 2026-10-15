data "google_compute_network" "this" {
  name = var.network
}

locals {
  labels = merge(var.labels, { environment = var.environment, managed-by = "opentofu" })

  is_prod          = var.environment == "prod"
  retained_backups = local.is_prod ? 30 : 7

  # DBA flags may tune the slow-query threshold, but identity login and
  # connection logging are applied last so no input can turn them off. People
  # and workloads log in with their Google identity, so the module never
  # creates or stores a password.
  database_flags = merge(
    { log_min_duration_statement = "1000" },
    var.database_flags,
    {
      "cloudsql.iam_authentication" = "on"
      log_connections               = "on"
      log_disconnections            = "on"
    },
  )
}

resource "google_sql_database_instance" "this" {
  name                = var.name
  database_version    = "POSTGRES_${var.postgres_version}"
  deletion_protection = var.deletion_protection

  settings {
    tier                        = var.tier
    edition                     = "ENTERPRISE"
    availability_type           = local.is_prod ? "REGIONAL" : "ZONAL"
    disk_type                   = "PD_SSD"
    disk_size                   = var.disk_size_gb
    disk_autoresize             = true
    deletion_protection_enabled = var.deletion_protection
    # Backups outlive the instance, so retiring one never loses its history.
    retain_backups_on_delete = true

    # Cloud SQL instances do not inherit the provider's default_labels.
    user_labels = local.labels

    ip_configuration {
      ipv4_enabled    = false
      private_network = data.google_compute_network.this.id
      ssl_mode        = "ENCRYPTED_ONLY"
    }

    backup_configuration {
      enabled                        = var.backups_enabled
      point_in_time_recovery_enabled = var.backups_enabled
      start_time                     = var.backup_start_time
      transaction_log_retention_days = 7

      backup_retention_settings {
        retained_backups = local.retained_backups
      }
    }

    maintenance_window {
      day          = var.maintenance_window.day
      hour         = var.maintenance_window.hour
      update_track = "stable"
    }

    insights_config {
      query_insights_enabled = true
    }

    dynamic "database_flags" {
      for_each = local.database_flags
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

resource "google_sql_user" "iam" {
  for_each = var.iam_users

  name     = each.value
  instance = google_sql_database_instance.this.name
  type     = "CLOUD_IAM_USER"
}
