# ---------------------------------------------------------------------------
# Standard Cloud SQL for PostgreSQL instance.
#
# Module-enforced standards (identical on every instance, not configurable):
#   * Private IP only, on the environment's apps-<env> VPC. No public IP.
#   * TLS required for all connections (ssl_mode = ENCRYPTED_ONLY).
#   * Cloud SQL IAM database authentication enabled; access is by Google
#     identity so the security team's audit trail is meaningful.
#   * Automated daily backups + point-in-time recovery, fixed retention.
#   * Fixed maintenance window (Sunday 03:00 UTC, stable track).
#   * SSD storage with autoresize enabled.
#   * Query Insights enabled.
#   * Deletion protection enabled (both API-level and Terraform-level).
#   * Standard resource labels.
# ---------------------------------------------------------------------------

data "google_compute_network" "apps" {
  # The network team owns these networks and has already configured private
  # services access on each; we only attach, never create or modify.
  name = "apps-${var.environment}"
}

locals {
  # Flags that encode the security standard. These always win and cannot be
  # overridden through var.database_flags (enforced by variable validation).
  standard_database_flags = {
    "cloudsql.iam_authentication" = "on"
  }

  database_flags = merge(var.database_flags, local.standard_database_flags)

  labels = {
    environment = var.environment
    component   = "postgresql"
    managed-by  = "opentofu"
  }
}

resource "google_sql_database_instance" "this" {
  name             = var.instance_name
  region           = var.region
  database_version = var.database_version

  # Terraform-level guard: refuse to destroy the instance. Removing an
  # instance must be a deliberate, reviewed two-step change, never a side
  # effect of a rename or refactor.
  deletion_protection = true

  settings {
    tier              = var.tier
    availability_type = var.availability_type
    edition           = "ENTERPRISE"

    disk_type       = "PD_SSD"
    disk_size       = var.disk_size_gb
    disk_autoresize = true

    # API-level guard, independent of Terraform state.
    deletion_protection_enabled = true

    user_labels = local.labels

    ip_configuration {
      # Private services access only. ipv4_enabled = false means no public
      # IP address is ever assigned; authorized networks are meaningless
      # and intentionally absent. ENCRYPTED_ONLY rejects unTLS'd clients.
      ipv4_enabled    = false
      private_network = data.google_compute_network.apps.id
      ssl_mode        = "ENCRYPTED_ONLY"
    }

    backup_configuration {
      enabled                        = true
      point_in_time_recovery_enabled = true
      start_time                     = "02:00"
      transaction_log_retention_days = 7

      backup_retention_settings {
        retained_backups = 14
        retention_unit   = "COUNT"
      }
    }

    maintenance_window {
      day          = 7 # Sunday
      hour         = 3 # 03:00 UTC
      update_track = "stable"
    }

    insights_config {
      query_insights_enabled  = true
      query_string_length     = 1024
      query_plans_per_minute  = 5
      record_application_tags = true
      record_client_address   = true
    }

    dynamic "database_flags" {
      for_each = local.database_flags
      content {
        name  = database_flags.key
        value = database_flags.value
      }
    }
  }
}

# ---------------------------------------------------------------------------
# Application databases.
# ---------------------------------------------------------------------------

resource "google_sql_database" "this" {
  for_each = var.databases

  name      = each.value
  instance  = google_sql_database_instance.this.name
  charset   = "UTF8"
  collation = "en_US.UTF8"
}

# ---------------------------------------------------------------------------
# IAM database users only.
#
# No password-based (BUILT_IN) users are created or managed by this module:
# humans and workloads authenticate with their existing Google identities,
# which is what the security team audits. The root postgres password is
# never generated or stored in Terraform state. In-database role grants are
# managed by the DBAs inside PostgreSQL.
# ---------------------------------------------------------------------------

resource "google_sql_user" "iam" {
  for_each = { for u in var.iam_database_users : u.id => u }

  instance = google_sql_database_instance.this.name
  type     = each.value.type

  # Cloud SQL registers service-account users without the
  # ".gserviceaccount.com" suffix.
  name = (
    each.value.type == "CLOUD_IAM_SERVICE_ACCOUNT"
    ? trimsuffix(each.value.id, ".gserviceaccount.com")
    : each.value.id
  )
}
