# ---------------------------------------------------------------------------
# Standard Cloud SQL for PostgreSQL instance.
#
# Decisions the module enforces on every instance (the "same everywhere" set):
#   * Private IP only — no public IP, ever. The instance hangs off the
#     environment VPC (apps-dev / apps-staging / apps-prod) through the
#     private services access the network team has already provisioned.
#   * Cloud IAM database authentication is forced on and cannot be switched
#     off via database_flags — the security team audits access by Google
#     identity, so identity-based login is non-negotiable.
#   * Encrypted client connections by default (ssl_mode = ENCRYPTED_ONLY).
#   * Query Insights is always enabled.
#   * Automated backups with point-in-time recovery on by default.
#   * deletion_protection on by default.
#   * activation_policy ALWAYS, pricing_plan PER_USE.
#
# Everything else — tier, version, availability, disk, flags, backup and
# maintenance windows, databases, users — is an input owned by the DBAs.
# ---------------------------------------------------------------------------

locals {
  network_project_id = coalesce(var.network_project_id, var.project_id)

  # Constructed rather than read through a data source: the network belongs
  # to the network team, and planning this module must not depend on API
  # reads against their resources.
  private_network = "projects/${local.network_project_id}/global/networks/${var.network}"

  # Module-enforced flags, merged last so they always win over var.database_flags.
  enforced_flags = {
    "cloudsql.iam_authentication" = "on"
  }
  database_flags = merge(var.database_flags, local.enforced_flags)
}

resource "google_sql_database_instance" "this" {
  project          = var.project_id
  name             = var.name
  region           = var.region
  database_version = var.database_version

  deletion_protection = var.deletion_protection
  encryption_key_name = var.encryption_key_name

  settings {
    tier                  = var.tier
    edition               = var.edition
    availability_type     = var.availability_type
    activation_policy     = "ALWAYS"
    pricing_plan          = "PER_USE"
    disk_type             = var.disk_type
    disk_size             = var.disk_size
    disk_autoresize       = var.disk_autoresize
    disk_autoresize_limit = var.disk_autoresize_limit

    ip_configuration {
      # Standard: private IP only, inside the environment VPC. The allocated
      # IP range is left to Google to pick from the PSA ranges the network
      # team provisioned.
      ipv4_enabled    = false
      private_network = local.private_network
      ssl_mode        = var.ssl_mode
    }

    backup_configuration {
      enabled                        = var.backup.enabled
      start_time                     = var.backup.start_time
      point_in_time_recovery_enabled = var.backup.point_in_time_recovery_enabled
      transaction_log_retention_days = var.backup.transaction_log_retention_days

      backup_retention_settings {
        retained_backups = var.backup.retained_backups
        retention_unit   = "COUNT"
      }
    }

    maintenance_window {
      day          = var.maintenance_window.day
      hour         = var.maintenance_window.hour
      update_track = var.maintenance_window.update_track
    }

    insights_config {
      query_insights_enabled  = true
      query_string_length     = var.query_insights.query_string_length
      record_application_tags = var.query_insights.record_application_tags
      record_client_address   = var.query_insights.record_client_address
      query_plans_per_minute  = var.query_insights.query_plans_per_minute
    }

    dynamic "database_flags" {
      for_each = local.database_flags
      content {
        name  = database_flags.key
        value = database_flags.value
      }
    }

    dynamic "password_validation_policy" {
      for_each = var.password_validation_policy == null ? [] : [var.password_validation_policy]
      content {
        enable_password_policy      = true
        min_length                  = password_validation_policy.value.min_length
        complexity                  = password_validation_policy.value.complexity
        reuse_interval              = password_validation_policy.value.reuse_interval
        disallow_username_substring = password_validation_policy.value.disallow_username_substring
        password_change_interval    = password_validation_policy.value.password_change_interval
      }
    }

    user_labels = var.labels
  }

  lifecycle {
    precondition {
      condition     = var.edition != "ENTERPRISE_PLUS" || startswith(var.tier, "db-perf-optimized-")
      error_message = "ENTERPRISE_PLUS edition requires a db-perf-optimized-* machine series tier."
    }
  }

  timeouts {
    create = "60m"
    update = "60m"
    delete = "60m"
  }
}
