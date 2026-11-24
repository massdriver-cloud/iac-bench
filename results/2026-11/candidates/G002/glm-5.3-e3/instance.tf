# =========================================================================
# The PostgreSQL instance
# =========================================================================
# Everything in this resource is either
#   * a standard the module imposes on every instance, or
#   * a per-instance decision exposed as a variable.
# See README.md for the rationale. Notably absent, on purpose:
#   * ipv4_enabled / authorized_networks - there is no public IP, ever.
#   * root_user / passwords - authentication is IAM only, so there is no
#     password to leak, rotate or put in a state file.
#   * a disabled backup_configuration - backups and PITR are always on.

resource "google_sql_database_instance" "this" {
  name             = var.name
  region           = var.region
  database_version = var.database_version
  project          = var.project

  # Customer-managed key for data at rest, when the DBA names one; null
  # falls back to Google-managed encryption.
  encryption_key_name = var.kms_key_name

  # Cloud SQL's own deletion protection: destroying the instance needs an
  # explicit opt-out in two places (here and in the console/gcloud), which
  # is exactly the friction a database deserves.
  deletion_protection = var.deletion_protection

  settings {
    tier              = var.tier
    edition           = var.edition
    availability_type = var.availability_type
    activation_policy = "ALWAYS"

    disk_size             = var.disk_size_gb
    disk_type             = var.disk_type
    disk_autoresize       = true
    disk_autoresize_limit = var.disk_autoresize_limit

    user_labels = local.user_labels

    # Private IP only, in the network the DBA named. No public IP, no
    # authorized networks: the instance is reachable only from var.network
    # and from networks peered with it through private services access.
    ip_configuration {
      ipv4_enabled       = false
      ssl_mode           = var.require_ssl ? "ENCRYPTED_ONLY" : "ALLOW_UNENCRYPTED_AND_ENCRYPTED"
      private_network    = local.private_network
      allocated_ip_range = var.allocated_ip_range
    }

    # Backups and point-in-time recovery are standards, not options. The
    # window and the retention periods are the DBA's to pick.
    backup_configuration {
      enabled                        = true
      start_time                     = var.backup_start_time
      point_in_time_recovery_enabled = true
      transaction_log_retention_days = var.transaction_log_retention_days

      backup_retention_settings {
        retained_backups = var.backup_retention_days
        retention_unit   = "COUNT"
      }
    }

    maintenance_window {
      day          = var.maintenance_window.day
      hour         = var.maintenance_window.hour
      update_track = var.maintenance_window.update_track
    }

    # Query Insights on every instance, so nobody has to guess what a
    # database was doing during an incident.
    insights_config {
      query_insights_enabled = true
      query_string_length    = var.query_string_length
      record_client_address  = var.record_client_address
    }

    # IAM database authentication. Together with IAM user registration this
    # is what lets the security team audit database access by identity.
    database_flags {
      name  = "cloudsql.iam_authentication"
      value = "on"
    }

    dynamic "database_flags" {
      for_each = var.database_flags

      content {
        name  = database_flags.key
        value = database_flags.value
      }
    }

    dynamic "location_preference" {
      for_each = var.zone == null ? [] : [var.zone]

      content {
        zone = location_preference.value
      }
    }
  }

  timeouts {
    create = "60m"
    update = "120m"
    delete = "30m"
  }

  lifecycle {
    precondition {
      condition     = var.zone == null || startswith(var.zone, var.region)
      error_message = "zone must be a zone inside region ('${var.region}-a'), or null."
    }

    precondition {
      condition     = var.edition != "ENTERPRISE_PLUS" || length(var.database_flags) == 0
      error_message = "ENTERPRISE_PLUS edition does not support custom database_flags. Use ENTERPRISE, or drop the flags."
    }

    precondition {
      condition     = var.kms_key_name == null || regex("/locations/[^/]+/", var.kms_key_name) == "/locations/${var.region}/"
      error_message = "The KMS key must live in the same region as the instance (${var.region})."
    }
  }
}
