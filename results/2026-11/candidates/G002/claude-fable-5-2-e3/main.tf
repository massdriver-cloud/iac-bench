locals {
  is_prod = var.environment == "prod"

  # One application network per environment, owned by the network team, with
  # private services access already in place. Referenced by path rather than
  # looked up so that the module needs no permissions on the network project.
  network_name    = "apps-${var.environment}"
  network_project = coalesce(var.network_project_id, var.project_id)
  network         = "projects/${local.network_project}/global/networks/${local.network_name}"

  # Environment-dependent standards (overridable where a variable exists).
  high_availability     = coalesce(var.high_availability, local.is_prod)
  backup_retained_count = coalesce(var.backup_retained_count, local.is_prod ? 30 : 7)
  # dev and staging take Cloud SQL maintenance releases before prod does.
  maintenance_track = local.is_prod ? "stable" : "canary"

  # Flags that are the same on every instance and cannot be overridden:
  # log in with Google identities, and leave an audit trail of who connected
  # and of every DDL and role/privilege change.
  enforced_flags = {
    "cloudsql.iam_authentication" = "on"
    "cloudsql.enable_pgaudit"     = "on"
    "pgaudit.log"                 = join(",", concat(["ddl", "role"], sort(tolist(var.pgaudit_extra_classes))))
    "log_connections"             = "on"
    "log_disconnections"          = "on"
  }

  # Operational logging defaults; DBAs may override these via database_flags.
  default_flags = {
    "log_checkpoints" = "on"
    "log_lock_waits"  = "on"
    "log_temp_files"  = "0"
  }

  database_flags = merge(local.default_flags, var.database_flags, local.enforced_flags)

  labels = merge(var.labels, {
    environment = var.environment
    managed-by  = "opentofu"
  })

  replica_names = { for k, v in var.read_replicas : k => "${var.name}-replica-${k}" }
}

###############################################################################
# Primary instance
###############################################################################

resource "google_sql_database_instance" "primary" {
  project          = var.project_id
  name             = var.name
  region           = var.region
  database_version = var.database_version

  encryption_key_name = var.kms_key_name

  # Blocks `tofu destroy` / replacement; settings.deletion_protection_enabled
  # below blocks deletion through the console, gcloud and the API as well.
  deletion_protection = var.deletion_protection

  settings {
    tier    = var.tier
    edition = var.edition

    availability_type = local.high_availability ? "REGIONAL" : "ZONAL"

    disk_type             = "PD_SSD"
    disk_size             = var.disk_size_gb
    disk_autoresize       = true
    disk_autoresize_limit = var.disk_autoresize_limit_gb

    deletion_protection_enabled = var.deletion_protection

    # If the instance is ever deleted, keep its backups and take a last one.
    retain_backups_on_delete = true

    final_backup_config {
      enabled        = true
      retention_days = 30
    }

    user_labels = local.labels

    # Private IP only, on the environment's application VPC. No public
    # address, no authorized networks, and TLS required on every connection.
    ip_configuration {
      ipv4_enabled       = false
      private_network    = local.network
      allocated_ip_range = var.allocated_ip_range
      ssl_mode           = "ENCRYPTED_ONLY"
    }

    backup_configuration {
      enabled                        = true
      point_in_time_recovery_enabled = true
      start_time                     = var.backup_start_time
      location                       = var.backup_location
      transaction_log_retention_days = var.transaction_log_retention_days

      backup_retention_settings {
        retained_backups = local.backup_retained_count
        retention_unit   = "COUNT"
      }
    }

    maintenance_window {
      day          = var.maintenance_window.day
      hour         = var.maintenance_window.hour
      update_track = local.maintenance_track
    }

    dynamic "deny_maintenance_period" {
      for_each = var.deny_maintenance_period == null ? [] : [var.deny_maintenance_period]

      content {
        start_date = deny_maintenance_period.value.start_date
        end_date   = deny_maintenance_period.value.end_date
        time       = deny_maintenance_period.value.time
      }
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

    insights_config {
      query_insights_enabled  = true
      query_string_length     = 1024
      query_plans_per_minute  = 5
      record_application_tags = true
      record_client_address   = true
    }

    # The module creates no password users. This applies to any built-in
    # user that is given a password out of band (e.g. break-glass use of
    # the default postgres user).
    password_validation_policy {
      enable_password_policy      = true
      min_length                  = 16
      complexity                  = "COMPLEXITY_DEFAULT"
      reuse_interval              = 5
      disallow_username_substring = true
    }
  }

  lifecycle {
    # Storage auto-grow is always on; without this, the first apply after the
    # disk has grown would try to shrink it back to disk_size_gb.
    ignore_changes = [settings[0].disk_size]

    precondition {
      condition     = length("${var.project_id}:${var.name}") <= 98
      error_message = "The combined length of project_id and name (\"<project_id>:<name>\") must not exceed 98 characters."
    }

    precondition {
      condition     = length(setintersection(keys(var.database_flags), keys(local.enforced_flags))) == 0
      error_message = "database_flags must not set cloudsql.iam_authentication, cloudsql.enable_pgaudit, pgaudit.log, log_connections or log_disconnections: these are enforced by the module. Use pgaudit_extra_classes to log more statement classes."
    }

    precondition {
      condition = var.edition == "ENTERPRISE_PLUS" ? (
        !can(regex("^db-(custom-|f1-micro$|g1-small$)", var.tier))
        ) : (
        !startswith(var.tier, "db-perf-optimized-")
      )
      error_message = "tier does not match edition: ENTERPRISE uses db-custom-<vcpus>-<memory_mb> tiers, ENTERPRISE_PLUS uses db-perf-optimized-N-<vcpus> tiers."
    }

    precondition {
      condition     = !(local.is_prod && contains(["db-f1-micro", "db-g1-small"], var.tier))
      error_message = "Shared-core tiers (db-f1-micro, db-g1-small) are not covered by the Cloud SQL SLA and are not allowed for prod."
    }

    precondition {
      condition     = var.edition == "ENTERPRISE_PLUS" || var.transaction_log_retention_days <= 7
      error_message = "transaction_log_retention_days can be at most 7 on the ENTERPRISE edition (up to 35 requires ENTERPRISE_PLUS)."
    }

    precondition {
      condition     = var.zone == null ? true : startswith(var.zone, "${var.region}-")
      error_message = "zone must be a zone within region."
    }
  }
}

###############################################################################
# Read replicas
###############################################################################

resource "google_sql_database_instance" "replica" {
  for_each = var.read_replicas

  project              = var.project_id
  name                 = local.replica_names[each.key]
  region               = coalesce(each.value.region, var.region)
  database_version     = var.database_version
  master_instance_name = google_sql_database_instance.primary.name

  encryption_key_name = each.value.kms_key_name != null ? each.value.kms_key_name : var.kms_key_name

  deletion_protection = var.deletion_protection

  settings {
    tier    = coalesce(each.value.tier, var.tier)
    edition = var.edition

    availability_type = "ZONAL"

    disk_type             = "PD_SSD"
    disk_autoresize       = true
    disk_autoresize_limit = var.disk_autoresize_limit_gb

    deletion_protection_enabled = var.deletion_protection

    user_labels = merge(local.labels, { replica-of = var.name })

    ip_configuration {
      ipv4_enabled       = false
      private_network    = local.network
      allocated_ip_range = var.allocated_ip_range
      ssl_mode           = "ENCRYPTED_ONLY"
    }

    dynamic "location_preference" {
      for_each = each.value.zone == null ? [] : [each.value.zone]

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

    insights_config {
      query_insights_enabled  = true
      query_string_length     = 1024
      query_plans_per_minute  = 5
      record_application_tags = true
      record_client_address   = true
    }
  }

  lifecycle {
    ignore_changes = [settings[0].disk_size]

    precondition {
      condition     = length("${var.project_id}:${local.replica_names[each.key]}") <= 98
      error_message = "The combined length of project_id and the replica name (\"<project_id>:<name>-replica-<key>\") must not exceed 98 characters."
    }

    precondition {
      condition = var.edition == "ENTERPRISE_PLUS" ? (
        !can(regex("^db-(custom-|f1-micro$|g1-small$)", coalesce(each.value.tier, var.tier)))
        ) : (
        !startswith(coalesce(each.value.tier, var.tier), "db-perf-optimized-")
      )
      error_message = "Replica tier does not match edition: ENTERPRISE uses db-custom-<vcpus>-<memory_mb> tiers, ENTERPRISE_PLUS uses db-perf-optimized-N-<vcpus> tiers."
    }

    precondition {
      condition     = each.value.zone == null ? true : startswith(each.value.zone, "${coalesce(each.value.region, var.region)}-")
      error_message = "A replica's zone must be a zone within the replica's region."
    }

    precondition {
      condition     = var.kms_key_name == null || coalesce(each.value.region, var.region) == var.region || each.value.kms_key_name != null
      error_message = "The primary uses a customer-managed key, and a key can only encrypt instances in its own region: a cross-region replica needs its own kms_key_name in the replica's region."
    }
  }
}

###############################################################################
# Databases
###############################################################################

resource "google_sql_database" "this" {
  for_each = var.databases

  project   = var.project_id
  instance  = google_sql_database_instance.primary.name
  name      = each.key
  charset   = each.value.charset
  collation = each.value.collation

  # Removing a database from the configuration must never drop its data.
  deletion_policy = "ABANDON"
}
