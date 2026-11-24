# ---------------------------------------------------------------------------
# Cloud SQL PostgreSQL instance.
#
# Design decisions baked in for consistency across the estate:
#   * Private IP by default; public IP opt-in via ipv4_enabled.
#   * IAM authentication enabled so access is audited by Google identity.
#   * Standard label set so every instance is identifiable by environment.
#   * No authorized networks by default; the public path stays closed unless
#     explicitly opened. Private services access is the only path in.
# ---------------------------------------------------------------------------

resource "google_sql_database_instance" "postgres" {
  name                = var.name
  project             = var.project_id
  region              = var.region
  database_version    = var.database_version
  deletion_protection = var.deletion_protection

  settings {
    tier              = var.tier
    availability_type = var.availability_type
    edition           = "ENTERPRISE"

    disk_size                   = var.disk_size_gb
    disk_autoresize             = var.disk_autoresize_limit_gb > 0
    disk_autoresize_limit       = var.disk_autoresize_limit_gb > 0 ? var.disk_autoresize_limit_gb : null
    disk_type                   = "PD_SSD"
    deletion_protection_enabled = var.deletion_protection

    ip_configuration {
      ipv4_enabled    = var.ipv4_enabled
      private_network = var.network

      allocated_ip_range = var.private_ip_allocated_range

      # TLS posture on the (opt-in) public path. Private path traffic never
      # leaves the VPC, but SSL is still enforced end-to-end for defense in depth.
      ssl_mode = var.require_ssl ? "TRUSTED_CLIENT_CERTIFICATE_REQUIRED" : "ALLOW_UNENCRYPTED_AND_ENCRYPTED"

      # Intentionally empty: no public source CIDRs are trusted by default.
      # The public path is opt-in and must be deliberately unlocked per instance.
    }

    backup_configuration {
      enabled                        = var.backup_enabled
      start_time                     = var.backup_start_time
      point_in_time_recovery_enabled = var.point_in_time_recovery_enabled
      transaction_log_retention_days = var.transaction_log_retention_days
      backup_retention_settings {
        retained_backups = var.retained_backups
        retention_unit   = "COUNT"
      }
    }

    maintenance_window {
      day          = var.maintenance_window_day
      hour         = var.maintenance_window_hour
      update_track = "stable"
    }

    database_flags {
      name  = "cloudsql.iam_authentication"
      value = "on"
    }

    user_labels = merge(
      {
        "managed-by"  = "tofu"
        "environment" = var.environment
        "engine"      = "postgresql"
        "ha"          = tostring(var.availability_type == "REGIONAL")
      },
      var.user_labels,
    )
  }

  lifecycle {
    prevent_destroy = var.deletion_protection
    ignore_changes = [
      settings[0].disk_size, # storage grows via auto-resize; don't fight drift
    ]
  }
}