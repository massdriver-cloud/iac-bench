terraform {
  required_version = ">= 1.0.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 4.0.0"
    }
  }
}

resource "google_sql_database_instance" "main" {
  name                = var.name
  project             = var.project_id
  region              = var.region
  database_version    = var.database_version
  deletion_protection = var.deletion_protection

  settings {
    tier                  = var.tier
    availability_type     = var.availability_type
    disk_size             = var.disk_size
    disk_type             = var.disk_type
    disk_autoresize       = var.disk_autoresize
    disk_autoresize_limit = var.disk_autoresize_limit
    user_labels           = var.labels

    ip_configuration {
      ipv4_enabled    = false
      private_network = var.network_id
    }

    backup_configuration {
      enabled                        = var.backup_enabled
      start_time                     = var.backup_start_time
      point_in_time_recovery_enabled = var.point_in_time_recovery_enabled
    }

    maintenance_window {
      day  = var.maintenance_day
      hour = var.maintenance_hour
    }

    dynamic "database_flags" {
      for_each = merge(var.database_flags, { "cloudsql.iam_authentication" = "on" })
      content {
        name  = database_flags.key
        value = database_flags.value
      }
    }
  }
}

resource "google_sql_user" "iam_users" {
  for_each = toset(var.iam_users)
  name     = each.value
  instance = google_sql_database_instance.main.name
  project  = var.project_id != null ? var.project_id : google_sql_database_instance.main.project
  type     = "CLOUD_IAM_USER"
}

resource "google_sql_user" "iam_service_accounts" {
  for_each = toset(var.iam_service_accounts)
  name     = each.value
  instance = google_sql_database_instance.main.name
  project  = var.project_id != null ? var.project_id : google_sql_database_instance.main.project
  type     = "CLOUD_IAM_SERVICE_ACCOUNT"
}
