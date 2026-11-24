# ===========================================================================
# Standard PostgreSQL module for the DBA team.
#
# Fleet-wide standards enforced here (not configurable per instance):
#   * Private IP only, in the environment's apps VPC. Public IPv4 is disabled.
#     The network team owns apps-dev / apps-staging / apps-prod and has already
#     configured private services access on each, so we only reference them.
#   * TLS required for all connections (ENCRYPTED_ONLY).
#   * IAM database authentication enabled + connection/disconnection logging,
#     so database access is auditable by Google identity.
#   * Automated daily backups with point-in-time recovery.
#   * Fixed maintenance window: Sunday 03:00, stable update track.
#   * Enterprise edition, Query Insights with application tags, disk
#     autoresize, standard labels, deletion protection on by default.
# ===========================================================================

# The environment VPC, owned by the network team. Private services access is
# already established on it; Cloud SQL attaches via private_network below.
data "google_compute_network" "apps" {
  name = "apps-${var.environment}"
}

locals {
  standard_labels = {
    environment = var.environment
    engine      = "postgres"
    managed-by  = "opentofu"
  }
}

resource "google_sql_database_instance" "this" {
  name             = var.instance_name
  database_version = var.database_version
  region           = var.region

  # OpenTofu-level guard against `tofu destroy` / replacement.
  deletion_protection = var.deletion_protection

  settings {
    edition           = "ENTERPRISE"
    tier              = var.tier
    availability_type = var.availability_type

    disk_type             = var.disk_type
    disk_size             = var.disk_size_gb
    disk_autoresize       = true
    disk_autoresize_limit = var.disk_autoresize_limit_gb

    # API-level guard against console/gcloud deletion.
    deletion_protection_enabled = var.deletion_protection

    user_labels = merge(local.standard_labels, var.user_labels)

    # Private connectivity only. No public IP, no authorized networks:
    # every application reaches the instance over the apps VPC.
    ip_configuration {
      ipv4_enabled    = false
      private_network = data.google_compute_network.apps.id
      ssl_mode        = "ENCRYPTED_ONLY"
    }

    # Backups and PITR are mandatory for every database in the fleet.
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
      query_string_length     = 2048
      record_application_tags = true
      record_client_address   = true
    }

    # IAM database authentication: humans and workloads log in as their
    # Google identity, which is what the security team audits. Connection
    # logging gives the audit trail on the database side.
    database_flags {
      name  = "cloudsql.iam_authentication"
      value = "on"
    }

    database_flags {
      name  = "log_connections"
      value = "on"
    }

    database_flags {
      name  = "log_disconnections"
      value = "on"
    }
  }
}

resource "google_sql_database" "this" {
  for_each = toset(var.databases)

  name     = each.value
  instance = google_sql_database_instance.this.name
}

# IAM database users only — no password users. IAM permissions and in-database
# GRANTs remain with the DBAs; this registers the identities Cloud SQL must
# recognize for IAM authentication.
resource "google_sql_user" "iam" {
  for_each = { for u in var.iam_users : u.email => u }

  instance = google_sql_database_instance.this.name
  type     = each.value.type

  # Cloud SQL expects service account users without the .gserviceaccount.com
  # suffix; human/user identities keep their full email.
  name = (
    each.value.type == "CLOUD_IAM_SERVICE_ACCOUNT"
    ? trimsuffix(each.value.email, ".gserviceaccount.com")
    : each.value.email
  )
}
