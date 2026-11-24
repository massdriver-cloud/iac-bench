# ---------------------------------------------------------------------------
# Team standards — the decisions that are the same on every instance.
# DBAs do not re-decide these per instance.
# ---------------------------------------------------------------------------

locals {
  # One custom VPC per environment, owned by the network team. Private
  # services access is already peered on each; the module only attaches.
  network_name = "apps-${var.environment}"

  # Environment policy: HA in staging/prod, single-zone in dev; newer
  # releases land in dev first (canary) before stable reaches staging/prod.
  availability_type = var.environment == "dev" ? "ZONAL" : "REGIONAL"
  update_track      = var.environment == "dev" ? "canary" : "stable"

  retained_backups = {
    dev     = 7
    staging = 14
    prod    = 30
  }

  # Mandatory flags: IAM database authentication (every login is a Google
  # identity, which is what the security team audits) plus a baseline of
  # audit/operational logging. DBA-supplied flags are merged underneath and
  # can never turn these off.
  standard_database_flags = {
    "cloudsql.iam_authentication" = "on"
    "log_checkpoints"             = "on"
    "log_connections"             = "on"
    "log_disconnections"          = "on"
    "log_lock_waits"              = "on"
    "log_temp_files"              = "0"
    "log_min_duration_statement"  = "1000"
    "log_min_messages"            = "warning"
  }

  database_flags = merge(var.database_flags, local.standard_database_flags)

  standard_labels = {
    managed-by  = "opentofu"
    environment = var.environment
    component   = "postgresql"
  }

  # Cloud SQL IAM service-account users are registered without the
  # ".gserviceaccount.com" suffix; human users keep their full email.
  iam_users = {
    for u in var.iam_database_users : u.email => {
      type = u.type
      name = u.type == "CLOUD_IAM_SERVICE_ACCOUNT" ? trimsuffix(u.email, ".gserviceaccount.com") : u.email
    }
  }
}

# Look up the environment's network in the provider's project (the same
# project the instance lives in). The network team owns it; we only read it.
data "google_compute_network" "apps" {
  name = local.network_name
}

resource "google_sql_database_instance" "this" {
  name             = var.instance_name
  region           = var.region
  database_version = var.database_version

  # Guard against accidental `tofu destroy`; mirrored at the API level below.
  deletion_protection = var.deletion_protection

  # No root_password: access is exclusively via IAM database authentication,
  # so no shared/built-in password credentials exist to leak or audit around.

  settings {
    tier              = var.tier
    edition           = "ENTERPRISE"
    availability_type = local.availability_type

    disk_type       = "PD_SSD"
    disk_autoresize = true

    deletion_protection_enabled = var.deletion_protection

    # Private IP only, on the environment's VPC via the existing private
    # services access connection. TLS is mandatory even inside the VPC.
    ip_configuration {
      ipv4_enabled                                  = false
      private_network                               = data.google_compute_network.apps.id
      ssl_mode                                      = "ENCRYPTED_ONLY"
      enable_private_path_for_google_cloud_services = false
    }

    # Backups and PITR are never optional.
    backup_configuration {
      enabled                        = true
      point_in_time_recovery_enabled = true
      start_time                     = "02:00"
      transaction_log_retention_days = 7

      backup_retention_settings {
        retained_backups = local.retained_backups[var.environment]
        retention_unit   = "COUNT"
      }
    }

    # One standard maintenance window: Sunday 03:00 UTC, after the 02:00
    # backup start. Dev rides the canary track, staging/prod ride stable.
    maintenance_window {
      day          = 7
      hour         = 3
      update_track = local.update_track
    }

    insights_config {
      query_insights_enabled  = true
      query_string_length     = 1024
      query_plans_per_minute  = 5
      record_application_tags = true
      record_client_address   = false
    }

    dynamic "database_flags" {
      for_each = local.database_flags
      content {
        name  = database_flags.key
        value = database_flags.value
      }
    }

    user_labels = merge(local.standard_labels, var.labels)
  }
}

# The application database, with the team-standard encoding/collation.
resource "google_sql_database" "app" {
  name      = var.database_name
  instance  = google_sql_database_instance.this.name
  charset   = "UTF8"
  collation = "en_US.UTF8"
}

# Database login is granted to Google identities only. The security team's
# audit trail is these IAM principals; no password users are managed here.
resource "google_sql_user" "iam" {
  for_each = local.iam_users

  name     = each.value.name
  instance = google_sql_database_instance.this.name
  type     = each.value.type
}
