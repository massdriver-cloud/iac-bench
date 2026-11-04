resource "google_sql_database_instance" "postgres" {
  name                = local.instance_name
  project             = var.project_id
  region              = var.region
  database_version    = "POSTGRES_15"
  deletion_protection = var.deletion_protection

  settings {
    tier                  = var.tier
    availability_type     = var.availability_type
    disk_type             = var.disk_type
    disk_size             = var.disk_size_gb
    disk_autoresize       = true
    disk_autoresize_limit = var.disk_autoresize_limit_gb
    user_labels           = local.all_labels
    activation_policy     = "ALWAYS"

    ip_configuration {
      ipv4_enabled    = false
      private_network = local.private_network
      ssl_mode        = "TRUSTED_CLIENT_CERTIFICATE_REQUIRED"
    }

    backup_configuration {
      enabled                        = var.backup_enabled
      start_time                     = var.backup_start_time
      point_in_time_recovery_enabled = true
      transaction_log_retention_days = var.backup_transaction_log_retention_days
      backup_retention_settings {
        retained_backups = var.backup_retention_count
        retention_unit   = "COUNT"
      }
    }

    maintenance_window {
      day          = var.maintenance_window_day
      hour         = var.maintenance_window_hour
      update_track = "stable"
    }

    dynamic "database_flags" {
      for_each = local.combined_flags
      content {
        name  = database_flags.key
        value = database_flags.value
      }
    }

    insights_config {
      query_insights_enabled  = true
      query_plans_per_minute  = 5
      query_string_length     = 1024
      record_application_tags = true
      record_client_address   = false
    }
  }

  lifecycle {
    prevent_destroy = var.deletion_protection
  }
}

resource "google_sql_database" "app" {
  name     = var.database_name
  instance = google_sql_database_instance.postgres.name
  project  = var.project_id

  depends_on = [google_sql_database_instance.postgres]
}

# PostgreSQL users are IAM-authenticated Google identities. The database user
# name is the full principal email; Cloud SQL maps that role to the OAuth
# identity during login, which is how the security team audits access.
resource "google_sql_user" "app_users" {
  for_each = var.users

  name     = each.value
  instance = google_sql_database_instance.postgres.name
  project  = var.project_id
  type     = "CLOUD_IAM_USER"

  depends_on = [google_sql_database.app]
}