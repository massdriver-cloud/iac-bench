locals {
  default_flags = {
    "cloudsql.iam_authentication" = "on"
  }
  # Enforce IAM authentication by putting default_flags last
  merged_flags = merge(var.database_flags, local.default_flags)
}

resource "google_sql_database_instance" "postgres" {
  name             = var.name
  database_version = var.database_version
  region           = var.region
  project          = var.project_id

  deletion_protection = var.deletion_protection

  settings {
    tier = var.tier

    availability_type = var.high_availability ? "REGIONAL" : "ZONAL"

    disk_size = var.disk_size
    disk_type = var.disk_type

    ip_configuration {
      ipv4_enabled    = false
      private_network = var.network_self_link
    }

    backup_configuration {
      enabled                        = var.enable_backups
      start_time                     = var.backup_start_time
      point_in_time_recovery_enabled = var.point_in_time_recovery_enabled
    }

    dynamic "database_flags" {
      for_each = local.merged_flags
      content {
        name  = database_flags.key
        value = database_flags.value
      }
    }

    user_labels = var.labels
  }
}

resource "google_sql_database" "dbs" {
  for_each = var.databases
  name     = each.key
  instance = google_sql_database_instance.postgres.name
  project  = var.project_id
}

resource "google_sql_user" "iam_users" {
  for_each = var.iam_user_emails
  name     = each.value
  instance = google_sql_database_instance.postgres.name
  project  = var.project_id
  type     = "CLOUD_IAM_USER"
}

resource "google_sql_user" "iam_service_accounts" {
  for_each = var.iam_service_account_emails
  name     = replace(each.value, ".gserviceaccount.com", "")
  instance = google_sql_database_instance.postgres.name
  project  = var.project_id
  type     = "CLOUD_IAM_SERVICE_ACCOUNT"
}
