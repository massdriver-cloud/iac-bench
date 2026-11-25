resource "google_sql_database_instance" "postgres" {
  project          = var.project_id
  name             = var.instance_name
  region           = var.region
  database_version = var.database_version

  # Protect both OpenTofu operations and out-of-band deletion.
  deletion_protection = var.deletion_protection

  settings {
    tier                        = var.tier
    availability_type           = var.availability_type
    disk_type                   = "PD_SSD"
    disk_size                   = var.disk_size_gb
    disk_autoresize             = true
    deletion_protection_enabled = var.deletion_protection
    user_labels                 = var.labels

    ip_configuration {
      ipv4_enabled    = false
      private_network = var.private_network
      ssl_mode        = "ENCRYPTED_ONLY"
    }

    backup_configuration {
      enabled                        = true
      start_time                     = var.backup_start_time
      point_in_time_recovery_enabled = true
      transaction_log_retention_days = 7
      backup_retention_settings {
        retained_backups = 7
        retention_unit   = "COUNT"
      }
    }

    maintenance_window {
      day          = var.maintenance_day
      hour         = var.maintenance_hour
      update_track = "stable"
    }

    database_flags {
      name  = "cloudsql.iam_authentication"
      value = "on"
    }
  }

  # Automatic storage growth is not a request to shrink the disk on the next plan.
  lifecycle {
    ignore_changes = [settings[0].disk_size]
  }
}

resource "google_sql_database" "database" {
  for_each = var.databases
  project  = var.project_id
  instance = google_sql_database_instance.postgres.name
  name     = each.value
}

resource "google_sql_user" "iam" {
  for_each = var.iam_users
  project  = var.project_id
  instance = google_sql_database_instance.postgres.name
  type     = each.value.type
  name     = each.value.type == "CLOUD_IAM_SERVICE_ACCOUNT" ? trimsuffix(each.value.email, ".gserviceaccount.com") : each.value.email
}
