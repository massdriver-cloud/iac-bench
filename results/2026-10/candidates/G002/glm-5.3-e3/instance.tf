###############################################################################
# The instance.
#
# Hard-coded, non-negotiable settings (see README "What this module decides"):
#   * private IP only - ipv4_enabled = false, no authorized networks, and no
#     variable exists to change that;
#   * TLS required on every connection (ssl_mode = ENCRYPTED_ONLY);
#   * IAM database authentication always on (database_flags in locals.tf);
#   * activation policy ALWAYS - databases do not sleep;
#   * baseline labels from locals.tf.
###############################################################################

resource "google_sql_database_instance" "this" {
  project          = var.project_id
  name             = var.name
  region           = var.region
  database_version = var.database_version

  # CMEK key (null = Google-managed encryption at rest). Granting the Cloud
  # SQL service agent access to the key is the security team's job.
  encryption_key_name = var.disk_encryption_key

  # Stateful resource: destruction must be a deliberate two-step act.
  deletion_protection = var.deletion_protection

  settings {
    tier                  = var.tier
    edition               = var.edition
    availability_type     = var.availability_type
    activation_policy     = "ALWAYS"
    disk_type             = var.disk_type
    disk_size             = var.disk_size
    disk_autoresize       = var.disk_autoresize
    disk_autoresize_limit = var.disk_autoresize_limit
    user_labels           = local.labels

    ip_configuration {
      ipv4_enabled    = false # no public IP, ever
      private_network = var.network
      ssl_mode        = "ENCRYPTED_ONLY" # TLS enforced even on private connections

      allocated_ip_range = var.allocated_ip_range
    }

    backup_configuration {
      enabled                        = var.backups_enabled
      start_time                     = var.backup_start_time
      point_in_time_recovery_enabled = var.point_in_time_recovery_enabled
      transaction_log_retention_days = var.transaction_log_retention_days

      backup_retention_settings {
        retained_backups = var.backup_retention_count
        retention_unit   = "COUNT"
      }
    }

    maintenance_window {
      day          = var.maintenance_window_day
      hour         = var.maintenance_window_hour
      update_track = var.maintenance_update_track
    }

    insights_config {
      query_insights_enabled = var.query_insights_enabled
    }

    dynamic "database_flags" {
      for_each = { for f in local.database_flags : f.name => f }
      content {
        name  = database_flags.value.name
        value = database_flags.value.value
      }
    }

    dynamic "location_preference" {
      for_each = var.zone == null ? toset([]) : toset([var.zone])
      content {
        zone = location_preference.value
      }
    }
  }

  depends_on = [google_project_service.sqladmin]
}
