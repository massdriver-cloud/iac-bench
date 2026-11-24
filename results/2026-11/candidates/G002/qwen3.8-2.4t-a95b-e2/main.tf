# ---------------------------------------------------------------------------
# Standard Cloud SQL PostgreSQL instance for the DBA team.
#
# Every decision that should be the same across all instances is fixed here:
# private-only networking into the environment's PSA network, IAM-only
# authentication (no password users, ever), backups with PITR always on,
# TLS required, SSD storage with auto-resize, locked audit flags, standard
# maintenance window, baseline labels, deletion protection.
#
# The decisions that genuinely vary per database (size, starting storage,
# version, availability in lower environments, retention, extra flags,
# initial IAM users, CMEK) live in variables.tf with deliberate defaults.
# ---------------------------------------------------------------------------

resource "google_sql_database_instance" "this" {
  project = var.project
  region  = var.region
  name    = var.name

  database_version    = var.database_version
  deletion_protection = var.deletion_protection
  encryption_key_name = var.encryption_key_name

  settings {
    tier              = var.tier
    availability_type = var.availability_type
    activation_policy = "ALWAYS"

    # SSD is the only sanctioned disk class; auto-resize means a full disk
    # never takes a database down.
    disk_type       = "PD_SSD"
    disk_size       = var.disk_size_gb
    disk_autoresize = true

    user_labels = local.labels

    dynamic "database_flags" {
      for_each = local.database_flags
      content {
        name  = database_flags.key
        value = database_flags.value
      }
    }

    ip_configuration {
      # Private IP only, via the PSA range the network team allocated on
      # apps-<environment>. No public IPv4, and therefore no authorized
      # networks to manage.
      ipv4_enabled       = false
      private_network    = local.private_network
      allocated_ip_range = var.allocated_ip_range

      # TLS is required even on the private network. The Cloud SQL Auth
      # Proxy and TLS-capable drivers satisfy this transparently.
      ssl_mode = "ENCRYPTED_ONLY"
    }

    backup_configuration {
      # Every database is backed up, and every database can be restored to
      # a point in time. There is no switch to turn either off. Transaction
      # logs are kept for the full 7 days to maximise the PITR window.
      enabled                        = true
      point_in_time_recovery_enabled = true
      start_time                     = "02:00"
      transaction_log_retention_days = 7

      backup_retention_settings {
        retained_backups = var.backup_retention_days
        retention_unit   = "COUNT"
      }
    }

    maintenance_window {
      day          = 7 # Sunday
      hour         = 4 # 04:00 UTC
      update_track = "stable"
    }

    insights_config {
      query_insights_enabled = true
    }
  }
}

# ---------------------------------------------------------------------------
# Initial database users, mapped to the Google identities our people and
# workloads already have. IAM users and service accounts only — this module
# has no concept of a database password.
# ---------------------------------------------------------------------------

resource "google_sql_user" "iam" {
  for_each = var.iam_database_users

  project  = var.project
  instance = google_sql_database_instance.this.name
  name     = each.value
  type     = endswith(each.value, ".iam.gserviceaccount.com") ? "CLOUD_IAM_SERVICE_ACCOUNT" : "CLOUD_IAM_USER"
}
