# Resolves the project of the ambient credentials when var.project is null,
# so the environment-standard network reference can be built. This makes no
# API calls.
data "google_client_config" "current" {}

# -----------------------------------------------------------------------------
# The Cloud SQL for PostgreSQL instance.
# -----------------------------------------------------------------------------
resource "google_sql_database_instance" "this" {
  project          = var.project
  name             = local.instance_name
  region           = var.region
  database_version = var.database_version

  # Guardrail: destroying a database must be a deliberate, two-step act.
  deletion_protection = var.deletion_protection

  settings {
    tier              = var.tier
    availability_type = var.availability_type

    # Storage always grows; shrinking/re-typing remains a DBA decision.
    disk_autoresize = true
    disk_size       = var.storage_gb
    disk_type       = var.disk_type

    user_labels = local.labels

    dynamic "database_flags" {
      for_each = local.database_flags
      content {
        name  = database_flags.key
        value = database_flags.value
      }
    }

    # Standard networking: private IP only, drawn from the environment's PSA
    # range. No public IPv4, ever. TLS required for every connection.
    ip_configuration {
      ipv4_enabled    = false
      private_network = local.network_self_link
      ssl_mode        = "ENCRYPTED_ONLY"
    }

    # Standard durability: automated backups and point-in-time recovery are
    # always on; retention and window timing are DBA decisions.
    backup_configuration {
      enabled                        = true
      point_in_time_recovery_enabled = true
      start_time                     = local.backup_start_time

      backup_retention_settings {
        retained_backups = var.backup_retention_days
        retention_unit   = "COUNT"
      }
    }

    # A defined maintenance window everywhere so patching is predictable
    # instead of "any time Google feels like it".
    maintenance_window {
      day  = var.maintenance_day
      hour = var.maintenance_hour
    }

    # Query Insights on everywhere: the DBA team can see what every workload
    # is actually doing without extra setup.
    insights_config {
      query_insights_enabled  = true
      query_string_length     = 1024
      record_application_tags = true
      record_client_address   = true
    }
  }
}

# -----------------------------------------------------------------------------
# Application databases.
# -----------------------------------------------------------------------------
resource "google_sql_database" "this" {
  for_each = toset(var.databases)

  project  = var.project
  instance = google_sql_database_instance.this.name
  name     = each.value
}

# -----------------------------------------------------------------------------
# Database principals. Only IAM identities — no password users. Connecting
# workloads/users also need roles/cloudsql.instanceUser (and
# roles/cloudsql.client) granted by the security team at project scope; that
# project-level IAM is deliberately out of this module's hands.
# -----------------------------------------------------------------------------
resource "google_sql_user" "iam_users" {
  for_each = var.iam_users

  project  = var.project
  instance = google_sql_database_instance.this.name
  name     = each.value
  type     = "CLOUD_IAM_USER"
}

resource "google_sql_user" "iam_service_accounts" {
  for_each = var.iam_service_accounts

  project  = var.project
  instance = google_sql_database_instance.this.name
  name     = each.value
  type     = "CLOUD_IAM_SERVICE_ACCOUNT"
}
