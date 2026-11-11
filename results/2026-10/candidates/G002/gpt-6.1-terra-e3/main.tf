resource "google_sql_database_instance" "postgres" {
  project          = var.project_id
  name             = var.instance_name
  region           = var.region
  database_version = var.database_version

  # Both OpenTofu and the Cloud SQL API must protect the instance from deletion.
  deletion_protection = true

  settings {
    tier                        = var.tier
    edition                     = "ENTERPRISE"
    availability_type           = "REGIONAL"
    disk_type                   = "PD_SSD"
    disk_size                   = var.disk_size_gb
    disk_autoresize             = true
    deletion_protection_enabled = true
    user_labels                 = var.labels

    ip_configuration {
      ipv4_enabled    = false
      private_network = var.private_network
      ssl_mode        = "ENCRYPTED_ONLY"
    }

    backup_configuration {
      enabled                        = true
      start_time                     = "03:00"
      point_in_time_recovery_enabled = true
      transaction_log_retention_days = 7
      backup_retention_settings {
        retained_backups = 7
        retention_unit   = "COUNT"
      }
    }

    maintenance_window {
      day          = 7
      hour         = 3
      update_track = "stable"
    }

    dynamic "database_flags" {
      for_each = merge(var.database_flags, { "cloudsql.iam_authentication" = "on" })
      content {
        name  = database_flags.key
        value = database_flags.value
      }
    }
  }

  # Cloud SQL increases storage automatically; don't try to reverse an increase.
  lifecycle {
    ignore_changes = [settings[0].disk_size]
  }
}

resource "google_sql_database" "databases" {
  for_each = var.databases
  project  = var.project_id
  instance = google_sql_database_instance.postgres.name
  name     = each.value
}

resource "google_sql_user" "iam" {
  for_each = var.iam_users
  project  = var.project_id
  instance = google_sql_database_instance.postgres.name
  name     = each.key
  type     = each.value
}
