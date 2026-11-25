locals {
  is_prod       = var.environment == "prod"
  instance_name = "${var.name}-${var.environment}"

  # The network team owns one VPC per environment and has already configured
  # private services access on each. The module attaches to it by name and
  # manages nothing on the network itself.
  network_project = coalesce(var.network_project_id, var.project_id)
  network         = "projects/${local.network_project}/global/networks/apps-${var.environment}"

  # Environment-driven defaults.
  high_availability      = coalesce(var.high_availability, local.is_prod)
  backup_retention_count = coalesce(var.backup_retention_count, local.is_prod ? 30 : 7)

  # Non-prod takes Cloud SQL maintenance releases first so that a bad release
  # is seen in dev and staging before it reaches prod.
  maintenance_track = local.is_prod ? "stable" : "canary"

  # Flags that are the same on every instance and cannot be overridden:
  # logins by Google identity, and an audit trail of who connected and what
  # privileged statements they ran.
  enforced_flags = {
    "cloudsql.iam_authentication" = "on"
    "cloudsql.enable_pgaudit"     = "on"
    "log_connections"             = "on"
    "log_disconnections"          = "on"
  }

  # Sensible logging defaults that DBAs may override through database_flags.
  default_flags = {
    "pgaudit.log"     = "role,ddl"
    "log_checkpoints" = "on"
    "log_lock_waits"  = "on"
    "log_temp_files"  = "0"
  }

  database_flags = merge(local.default_flags, var.database_flags, local.enforced_flags)

  labels = merge(var.labels, {
    environment = var.environment
    service     = var.name
    managed-by  = "opentofu"
  })
}

resource "google_sql_database_instance" "this" {
  project          = var.project_id
  name             = local.instance_name
  region           = var.region
  database_version = var.database_version

  encryption_key_name = var.kms_key_name

  # Guards against `tofu destroy` / replacement; the API-level guard is in
  # settings below.
  deletion_protection = var.deletion_protection

  settings {
    edition           = var.edition
    tier              = var.tier
    availability_type = local.high_availability ? "REGIONAL" : "ZONAL"
    activation_policy = "ALWAYS"

    disk_type             = "PD_SSD"
    disk_size             = var.disk_size_gb
    disk_autoresize       = true
    disk_autoresize_limit = var.disk_autoresize_limit_gb

    deletion_protection_enabled = var.deletion_protection

    # Production instances keep their backups, plus one final backup, if the
    # instance is ever deleted. Dev and staging clean up after themselves.
    retain_backups_on_delete = local.is_prod

    dynamic "final_backup_config" {
      for_each = local.is_prod ? [1] : []
      content {
        enabled        = true
        retention_days = 30
      }
    }

    user_labels = local.labels

    # Private IP only, on the environment's VPC. No public address, no
    # authorised networks, and TLS on every connection.
    ip_configuration {
      ipv4_enabled       = false
      private_network    = local.network
      allocated_ip_range = var.allocated_ip_range
      ssl_mode           = "ENCRYPTED_ONLY"
    }

    # Backups and point-in-time recovery are always on; only the schedule and
    # retention are tunable.
    backup_configuration {
      enabled                        = true
      start_time                     = var.backup_start_time
      location                       = var.backup_location
      point_in_time_recovery_enabled = true
      transaction_log_retention_days = var.transaction_log_retention_days

      backup_retention_settings {
        retained_backups = local.backup_retention_count
        retention_unit   = "COUNT"
      }
    }

    maintenance_window {
      day          = var.maintenance_window.day
      hour         = var.maintenance_window.hour
      update_track = local.maintenance_track
    }

    insights_config {
      query_insights_enabled  = true
      query_string_length     = 1024
      record_application_tags = true
      record_client_address   = true
    }

    dynamic "location_preference" {
      for_each = var.zone == null ? [] : [var.zone]
      content {
        zone = location_preference.value
      }
    }

    dynamic "database_flags" {
      for_each = local.database_flags
      content {
        name  = database_flags.key
        value = database_flags.value
      }
    }
  }

  lifecycle {
    # Storage auto-grows; without this, the next apply would try to shrink the
    # disk back to disk_size_gb, which Cloud SQL rejects.
    ignore_changes = [settings[0].disk_size]

    precondition {
      condition     = length(setintersection(keys(var.database_flags), keys(local.enforced_flags))) == 0
      error_message = "database_flags must not set ${join(", ", keys(local.enforced_flags))}: the module enforces these on every instance."
    }

    precondition {
      condition     = !(var.edition == "ENTERPRISE_PLUS" && can(regex("^db-(custom-|f1-micro$|g1-small$)", var.tier)))
      error_message = "ENTERPRISE_PLUS does not support db-custom-* or shared-core machine types; use the db-perf-optimized-N-* family."
    }

    precondition {
      condition     = !(var.edition == "ENTERPRISE" && startswith(var.tier, "db-perf-optimized-"))
      error_message = "db-perf-optimized-* machine types require edition = \"ENTERPRISE_PLUS\"."
    }

    precondition {
      condition     = !(local.is_prod && contains(["db-f1-micro", "db-g1-small"], var.tier))
      error_message = "Shared-core machine types (db-f1-micro, db-g1-small) are not covered by the Cloud SQL SLA and are not allowed in prod."
    }

    precondition {
      condition     = var.edition == "ENTERPRISE_PLUS" || var.transaction_log_retention_days <= 7
      error_message = "transaction_log_retention_days above 7 requires edition = \"ENTERPRISE_PLUS\"."
    }

    precondition {
      condition     = var.zone == null ? true : startswith(var.zone, "${var.region}-")
      error_message = "zone must be a zone in the instance's region."
    }
  }
}

resource "google_sql_database" "this" {
  for_each = var.databases

  project   = var.project_id
  instance  = google_sql_database_instance.this.name
  name      = each.value
  charset   = "UTF8"
  collation = "en_US.UTF8"

  # Removing a database from the list must never drop data. The database is
  # released from state and a DBA drops it by hand when that is really meant.
  deletion_policy = "ABANDON"
}
