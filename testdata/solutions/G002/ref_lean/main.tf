data "google_compute_network" "this" {
  name = var.network
}

locals {
  is_prod          = var.environment == "prod"
  retained_backups = local.is_prod ? 30 : 7

  # Connection and slow-query logging are the same on every instance; DBA
  # flags layer on top and win on conflict.
  database_flags = merge(
    {
      log_connections            = "on"
      log_disconnections         = "on"
      log_min_duration_statement = "1000"
    },
    var.database_flags,
  )
}

resource "random_password" "postgres" {
  length  = 32
  special = false
}

resource "google_sql_database_instance" "this" {
  name                = var.name
  database_version    = "POSTGRES_${var.postgres_version}"
  root_password       = random_password.postgres.result
  deletion_protection = var.deletion_protection

  settings {
    tier                        = var.tier
    edition                     = "ENTERPRISE"
    availability_type           = local.is_prod ? "REGIONAL" : "ZONAL"
    disk_type                   = "PD_SSD"
    disk_size                   = var.disk_size_gb
    disk_autoresize             = true
    deletion_protection_enabled = var.deletion_protection

    user_labels = merge(var.labels, { environment = var.environment })

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
