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
    disk_autoresize             = true
    disk_size                   = var.disk_size_gb
    deletion_protection_enabled = var.deletion_protection
    user_labels                 = { environment = var.environment }

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
  }

  lifecycle {
    # Never attempt to undo a service-initiated storage increase.
    ignore_changes = [settings[0].disk_size]
  }
}

resource "google_sql_database" "app" {
  for_each = var.databases
  instance = google_sql_database_instance.postgres.name
  name     = each.key
}

resource "google_sql_user" "human" {
  for_each = var.iam_users
  instance = google_sql_database_instance.postgres.name
  name     = each.key
  type     = "CLOUD_IAM_USER"
}

resource "google_sql_user" "workload" {
  for_each = var.iam_service_accounts
  instance = google_sql_database_instance.postgres.name
  name     = trimsuffix(each.key, ".gserviceaccount.com")
  type     = "CLOUD_IAM_SERVICE_ACCOUNT"
}
