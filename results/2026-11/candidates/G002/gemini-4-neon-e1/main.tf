data "google_client_config" "current" {}

data "google_compute_network" "vpc" {
  name = local.network_name
}

################################################################################
# Primary Cloud SQL PostgreSQL Instance
################################################################################

resource "google_sql_database_instance" "primary" {
  name                = local.instance_name
  database_version    = var.postgres_version
  region              = local.region
  deletion_protection = local.deletion_protection
  encryption_key_name = var.encryption_key_name

  settings {
    edition                          = var.edition
    tier                             = local.tier
    availability_type                = local.availability_type
    disk_type                        = var.disk_type
    disk_size                        = local.disk_size_gb
    disk_autoresize                  = true
    disk_autoresize_limit            = var.disk_autoresize_limit_gb
    data_disk_provisioned_iops       = var.disk_provisioned_iops
    data_disk_provisioned_throughput = var.disk_provisioned_throughput
    deletion_protection_enabled      = local.deletion_protection
    retain_backups_on_delete         = var.environment != "dev"
    connector_enforcement            = var.connector_enforcement
    user_labels                      = local.primary_labels

    ip_configuration {
      ipv4_enabled                                  = false
      private_network                               = data.google_compute_network.vpc.id
      allocated_ip_range                            = var.allocated_ip_range
      enable_private_path_for_google_cloud_services = true
      ssl_mode                                      = "ENCRYPTED_ONLY"
    }

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
      update_track = local.update_track
    }

    dynamic "deny_maintenance_period" {
      for_each = var.deny_maintenance_period != null ? [var.deny_maintenance_period] : []
      content {
        start_date = deny_maintenance_period.value.start_date
        end_date   = deny_maintenance_period.value.end_date
        time       = deny_maintenance_period.value.time
      }
    }

    insights_config {
      query_insights_enabled  = true
      query_plans_per_minute  = var.insights_query_plans_per_minute
      query_string_length     = var.insights_query_string_length
      record_application_tags = true
      record_client_address   = true
    }

    password_validation_policy {
      enable_password_policy      = true
      min_length                  = 16
      complexity                  = "COMPLEXITY_DEFAULT"
      reuse_interval              = 5
      disallow_username_substring = true
    }

    dynamic "data_cache_config" {
      for_each = var.edition == "ENTERPRISE_PLUS" ? [1] : []
      content {
        data_cache_enabled = var.data_cache_enabled
      }
    }

    dynamic "location_preference" {
      for_each = (var.zone != null || var.secondary_zone != null) ? [1] : []
      content {
        zone           = var.zone
        secondary_zone = var.secondary_zone
      }
    }

    dynamic "database_flags" {
      for_each = local.primary_database_flags
      content {
        name  = database_flags.key
        value = database_flags.value
      }
    }
  }

  lifecycle {
    # disk_autoresize is always enabled; ignore drift once Cloud SQL grows the disk
    # so subsequent applies do not fail attempting to shrink storage.
    ignore_changes = [
      settings[0].disk_size,
    ]

    precondition {
      condition     = !var.data_cache_enabled || var.edition == "ENTERPRISE_PLUS"
      error_message = "data_cache_enabled can only be true when edition is 'ENTERPRISE_PLUS'."
    }

    precondition {
      condition     = var.edition == "ENTERPRISE_PLUS" || var.transaction_log_retention_days <= 7
      error_message = "transaction_log_retention_days must be <= 7 for ENTERPRISE edition (up to 14 requires ENTERPRISE_PLUS)."
    }

    precondition {
      condition     = var.environment == "dev" || local.backup_retention_count >= 7
      error_message = "backup_retention_count must be at least 7 in staging and prod environments."
    }

    precondition {
      condition     = var.edition == "ENTERPRISE_PLUS" ? startswith(local.tier, "db-perf-optimized-N-") : !startswith(local.tier, "db-perf-optimized-N-")
      error_message = "tier '${local.tier}' is incompatible with edition '${var.edition}' (ENTERPRISE_PLUS requires db-perf-optimized-N-* tiers)."
    }

    precondition {
      condition     = var.disk_autoresize_limit_gb == 0 || var.disk_autoresize_limit_gb >= local.disk_size_gb
      error_message = "disk_autoresize_limit_gb (${var.disk_autoresize_limit_gb}) must be 0 (unlimited) or >= disk_size_gb (${local.disk_size_gb})."
    }

    precondition {
      condition     = (var.disk_provisioned_iops == null && var.disk_provisioned_throughput == null) || var.disk_type == "HYPERDISK_BALANCED"
      error_message = "disk_provisioned_iops and disk_provisioned_throughput can only be set when disk_type is 'HYPERDISK_BALANCED'."
    }

    precondition {
      condition     = var.secondary_zone == null || local.availability_type == "REGIONAL"
      error_message = "secondary_zone can only be set when availability_type is 'REGIONAL'."
    }
  }
}

################################################################################
# Read Replicas
################################################################################

resource "google_sql_database_instance" "read_replica" {
  for_each = var.read_replicas

  name                 = local.replica_names[each.key]
  master_instance_name = google_sql_database_instance.primary.name
  database_version     = var.postgres_version
  region               = coalesce(each.value.region, local.region)
  deletion_protection  = each.value.deletion_protection != null ? each.value.deletion_protection : local.deletion_protection
  encryption_key_name  = each.value.encryption_key_name != null ? each.value.encryption_key_name : var.encryption_key_name

  settings {
    edition                     = var.edition
    tier                        = coalesce(each.value.tier, local.tier)
    availability_type           = each.value.availability_type
    disk_type                   = coalesce(each.value.disk_type, var.disk_type)
    disk_autoresize             = true
    disk_autoresize_limit       = coalesce(each.value.disk_autoresize_limit_gb, var.disk_autoresize_limit_gb)
    deletion_protection_enabled = each.value.deletion_protection != null ? each.value.deletion_protection : local.deletion_protection
    connector_enforcement       = var.connector_enforcement
    user_labels = merge(
      var.labels,
      each.value.labels,
      local.enforced_labels,
      {
        role    = "read_replica"
        replica = each.key
      },
    )

    ip_configuration {
      ipv4_enabled                                  = false
      private_network                               = data.google_compute_network.vpc.id
      allocated_ip_range                            = each.value.allocated_ip_range != null ? each.value.allocated_ip_range : var.allocated_ip_range
      enable_private_path_for_google_cloud_services = true
      ssl_mode                                      = "ENCRYPTED_ONLY"
    }

    insights_config {
      query_insights_enabled  = true
      query_plans_per_minute  = var.insights_query_plans_per_minute
      query_string_length     = var.insights_query_string_length
      record_application_tags = true
      record_client_address   = true
    }

    dynamic "data_cache_config" {
      for_each = var.edition == "ENTERPRISE_PLUS" ? [1] : []
      content {
        data_cache_enabled = each.value.data_cache_enabled != null ? each.value.data_cache_enabled : var.data_cache_enabled
      }
    }

    dynamic "location_preference" {
      for_each = each.value.zone != null ? [1] : []
      content {
        zone = each.value.zone
      }
    }

    dynamic "database_flags" {
      for_each = merge(
        local.default_operational_flags,
        var.database_flags,
        each.value.database_flags,
        local.enforced_security_flags,
      )
      content {
        name  = database_flags.key
        value = database_flags.value
      }
    }
  }

  lifecycle {
    ignore_changes = [
      settings[0].disk_size,
    ]

    precondition {
      condition     = !(each.value.data_cache_enabled == true) || var.edition == "ENTERPRISE_PLUS"
      error_message = "Read replica '${each.key}' cannot enable data_cache_enabled unless edition is 'ENTERPRISE_PLUS'."
    }

    precondition {
      condition = (
        var.edition == "ENTERPRISE_PLUS"
        ? startswith(coalesce(each.value.tier, local.tier), "db-perf-optimized-N-")
        : !startswith(coalesce(each.value.tier, local.tier), "db-perf-optimized-N-")
      )
      error_message = "Read replica '${each.key}' tier is incompatible with edition '${var.edition}'."
    }
  }
}

################################################################################
# Logical PostgreSQL Databases
################################################################################

resource "google_sql_database" "databases" {
  for_each = var.databases

  name            = each.key
  instance        = google_sql_database_instance.primary.name
  charset         = each.value.charset
  collation       = each.value.collation
  deletion_policy = coalesce(each.value.deletion_policy, local.profile.db_deletion_policy)
}
