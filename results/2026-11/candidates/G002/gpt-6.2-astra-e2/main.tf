terraform {
  required_version = ">= 1.6.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 6.0, < 8.0"
    }
  }
}

data "google_compute_network" "apps" {
  name = "apps-${var.environment}"
}

resource "google_sql_database_instance" "postgres" {
  name                = var.instance_name
  region              = var.region
  database_version    = var.database_version
  deletion_protection = var.deletion_protection

  settings {
    edition                     = var.edition
    tier                        = var.tier
    availability_type           = var.availability_type
    disk_type                   = "PD_SSD"
    disk_size                   = var.disk_size_gb
    disk_autoresize             = true
    deletion_protection_enabled = var.deletion_protection

    ip_configuration {
      ipv4_enabled    = false
      private_network = data.google_compute_network.apps.self_link
      ssl_mode        = "ENCRYPTED_ONLY"
    }

    backup_configuration {
      enabled                        = true
      point_in_time_recovery_enabled = true
      start_time                     = var.backup_start_time
      transaction_log_retention_days = 7
      backup_retention_settings {
        retained_backups = 7
        retention_unit   = "COUNT"
      }
    }

    dynamic "database_flags" {
      for_each = merge(var.database_flags, { "cloudsql.iam_authentication" = "on" })
      content {
        name  = database_flags.key
        value = database_flags.value
      }
    }

    dynamic "maintenance_window" {
      for_each = var.maintenance_window[*]
      content {
        day  = maintenance_window.value.day
        hour = maintenance_window.value.hour
      }
    }
  }
  lifecycle {
    # Cloud SQL cannot shrink a disk after automatic growth.
    ignore_changes = [settings[0].disk_size]
  }
}

resource "google_sql_database" "application" {
  for_each = var.databases
  name     = each.value
  instance = google_sql_database_instance.postgres.name
}

resource "google_sql_user" "identity" {
  for_each = var.iam_users
  instance = google_sql_database_instance.postgres.name
  name     = each.value == "CLOUD_IAM_SERVICE_ACCOUNT" ? trimsuffix(each.key, ".gserviceaccount.com") : each.key
  type     = each.value
}

output "connection_name" {
  description = "Instance connection name for Cloud SQL connectors."
  value       = google_sql_database_instance.postgres.connection_name
}

output "private_ip_address" {
  description = "PostgreSQL private endpoint in the selected environment."
  value       = google_sql_database_instance.postgres.private_ip_address
}

output "instance_name" {
  value = google_sql_database_instance.postgres.name
}
