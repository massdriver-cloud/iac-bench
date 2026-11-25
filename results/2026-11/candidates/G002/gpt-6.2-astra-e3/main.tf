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
  name                = var.name
  region              = var.region
  database_version    = var.database_version
  deletion_protection = var.deletion_protection

  settings {
    edition                     = var.edition
    tier                        = var.tier
    availability_type           = var.availability_type
    disk_size                   = var.disk_size_gb
    disk_type                   = "PD_SSD"
    disk_autoresize             = true
    deletion_protection_enabled = var.deletion_protection

    ip_configuration {
      ipv4_enabled    = false
      private_network = data.google_compute_network.apps.self_link
      ssl_mode        = "ENCRYPTED_ONLY"
    }

    backup_configuration {
      enabled                        = true
      start_time                     = var.backup_start_time
      point_in_time_recovery_enabled = true
      transaction_log_retention_days = 7
      backup_retention_settings {
        retained_backups = 14
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

  # Never request a shrink after Cloud SQL has automatically grown the disk.
  lifecycle {
    ignore_changes = [settings[0].disk_size]
  }
}

resource "google_sql_database" "database" {
  for_each = var.databases
  name     = each.key
  instance = google_sql_database_instance.postgres.name
}

resource "google_sql_user" "human" {
  for_each = var.iam_users
  name     = each.key
  type     = "CLOUD_IAM_USER"
  instance = google_sql_database_instance.postgres.name
}

resource "google_sql_user" "workload" {
  for_each = var.iam_service_accounts
  name     = trimsuffix(each.key, ".gserviceaccount.com")
  type     = "CLOUD_IAM_SERVICE_ACCOUNT"
  instance = google_sql_database_instance.postgres.name
}

output "connection_name" {
  description = "Instance connection name for Cloud SQL connectors."
  value       = google_sql_database_instance.postgres.connection_name
}

output "private_ip_address" {
  description = "PostgreSQL private endpoint."
  value       = google_sql_database_instance.postgres.private_ip_address
}
