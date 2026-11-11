resource "google_sql_database_instance" "postgres" {
  project             = var.project_id
  name                = var.instance_name
  region              = var.region
  database_version    = var.database_version
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
      transaction_log_retention_days = var.transaction_log_retention_days

      backup_retention_settings {
        retained_backups = var.retained_backups
        retention_unit   = "COUNT"
      }
    }

    insights_config {
      query_insights_enabled = true
    }

    dynamic "maintenance_window" {
      for_each = var.maintenance_window == null ? [] : [var.maintenance_window]
      content {
        day          = maintenance_window.value.day
        hour         = maintenance_window.value.hour
        update_track = maintenance_window.value.update_track
      }
    }

    dynamic "database_flags" {
      for_each = merge(var.database_flags, {
        "cloudsql.iam_authentication" = "on"
        "log_connections"             = "on"
        "log_disconnections"          = "on"
      })
      content {
        name  = database_flags.key
        value = database_flags.value
      }
    }
  }

  lifecycle {
    # Cloud SQL automatically increases disk size; never attempt to shrink it back.
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
  name     = each.key
  type     = each.value
}
