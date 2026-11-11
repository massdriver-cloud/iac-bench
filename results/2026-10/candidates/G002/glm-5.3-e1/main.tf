###############################################################################
# The instance
###############################################################################

resource "google_sql_database_instance" "instance" {
  name             = var.name
  region           = var.region
  database_version = local.database_version

  # Destroying a database is a deliberate, reviewed act - not something a
  # stray `tofu destroy` should be able to do. Both guards are always on:
  # this one is OpenTofu's, the one in settings is the Cloud SQL API's own.
  deletion_protection = true

  settings {
    tier              = var.tier
    edition           = var.edition
    availability_type = local.availability_type

    disk_type       = var.disk_type
    disk_size       = var.disk_size_gb
    disk_autoresize = true

    deletion_protection_enabled = true
    user_labels                 = local.labels

    # Private IP only. Consumers are GKE and Compute Engine workloads inside
    # apps-<environment>, where the network team has already set up private
    # services access. There is deliberately no public IP, no
    # authorized-networks escape hatch, and every connection is TLS-encrypted
    # (client certificates are not required: IAM logins authenticate with an
    # OAuth token, not a certificate).
    ip_configuration {
      ipv4_enabled    = false
      private_network = local.private_network
      ssl_mode        = "ENCRYPTED_ONLY"
    }

    # Backups and point-in-time recovery are not optional.
    backup_configuration {
      enabled                        = true
      start_time                     = var.backup_start_time
      point_in_time_recovery_enabled = var.pitr_enabled
      transaction_log_retention_days = var.pitr_enabled ? local.transaction_log_retention_days : null

      backup_retention_settings {
        retained_backups = local.backup_retention_days
        retention_unit   = "COUNT"
      }
    }

    # Query Insights is how the DBA team sees what the database is doing.
    insights_config {
      query_insights_enabled  = true
      query_string_length     = 4096
      record_client_address   = true
      record_application_tags = true
    }

    # Minor version updates land in the window the DBAs picked, on the stable
    # update track.
    maintenance_window {
      day          = var.maintenance_window_day
      hour         = var.maintenance_window_hour
      update_track = "stable"
    }

    dynamic "database_flags" {
      for_each = local.database_flags
      content {
        name  = database_flags.key
        value = database_flags.value
      }
    }

    dynamic "location_preference" {
      for_each = var.preferred_zone == null ? [] : [var.preferred_zone]
      content {
        zone = location_preference.value
      }
    }
  }

  lifecycle {
    # Storage auto-resize is on, so the autoscaler - not this module - owns
    # the disk size after creation. Cloud SQL disks cannot shrink, so a plan
    # must never try to "correct" an automatic resize back down to the
    # initial size.
    ignore_changes = [settings[0].disk_size]
  }
}
