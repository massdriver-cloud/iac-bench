resource "google_sql_database_instance" "primary" {
  name                = var.name
  database_version    = var.database_version
  region              = local.region
  encryption_key_name = var.encryption_key_name
  deletion_protection = local.deletion_protection

  settings {
    edition                     = var.edition
    tier                        = local.tier
    availability_type           = local.availability_type
    disk_size                   = local.disk_size
    disk_type                   = var.disk_type
    disk_autoresize             = true
    disk_autoresize_limit       = var.disk_autoresize_limit
    deletion_protection_enabled = local.deletion_protection
    retain_backups_on_delete    = local.retain_backups_on_delete
    connector_enforcement       = var.connector_enforcement
    user_labels                 = local.primary_labels

    ip_configuration {
      ipv4_enabled                                  = false
      private_network                               = data.google_compute_network.vpc.id
      allocated_ip_range                            = var.allocated_ip_range
      ssl_mode                                      = "ENCRYPTED_ONLY"
      enable_private_path_for_google_cloud_services = true
    }

    backup_configuration {
      enabled                        = true
      point_in_time_recovery_enabled = true
      start_time                     = var.backup_configuration.start_time
      location                       = var.backup_configuration.location
      transaction_log_retention_days = local.transaction_log_retention_days

      backup_retention_settings {
        retained_backups = local.retained_backups
        retention_unit   = "COUNT"
      }
    }

    maintenance_window {
      day          = var.maintenance_window.day
      hour         = var.maintenance_window.hour
      update_track = local.maintenance_update_track
    }

    dynamic "deny_maintenance_period" {
      for_each = var.deny_maintenance_period != null ? [var.deny_maintenance_period] : []
      content {
        start_date = deny_maintenance_period.value.start_date
        end_date   = deny_maintenance_period.value.end_date
        time       = deny_maintenance_period.value.time
      }
    }

    dynamic "location_preference" {
      for_each = var.zone != null || var.secondary_zone != null ? [1] : []
      content {
        zone           = var.zone
        secondary_zone = var.secondary_zone
      }
    }

    insights_config {
      query_insights_enabled  = true
      query_string_length     = var.query_insights.query_string_length
      record_application_tags = true
      record_client_address   = true
      query_plans_per_minute  = var.query_insights.query_plans_per_minute
    }

    password_validation_policy {
      enable_password_policy      = true
      min_length                  = 16
      complexity                  = "COMPLEXITY_DEFAULT"
      disallow_username_substring = true
    }

    dynamic "data_cache_config" {
      for_each = var.edition == "ENTERPRISE_PLUS" ? [1] : []
      content {
        data_cache_enabled = var.data_cache_enabled
      }
    }

    dynamic "database_flags" {
      for_each = local.effective_database_flags
      content {
        name  = database_flags.key
        value = database_flags.value
      }
    }
  }

  lifecycle {
    precondition {
      condition     = local.region != ""
      error_message = "A GCP region must be specified either via var.region or on the Google provider."
    }

    precondition {
      condition     = !var.data_cache_enabled || var.edition == "ENTERPRISE_PLUS"
      error_message = "data_cache_enabled = true requires edition = \"ENTERPRISE_PLUS\"."
    }

    precondition {
      condition     = local.transaction_log_retention_days <= local.max_transaction_log_retention_days
      error_message = "backup_configuration.transaction_log_retention_days (${local.transaction_log_retention_days}) exceeds the maximum (${local.max_transaction_log_retention_days}) for edition ${var.edition}."
    }

    precondition {
      condition     = var.secondary_zone == null || local.availability_type == "REGIONAL"
      error_message = "secondary_zone can only be specified when availability_type is \"REGIONAL\"."
    }

    precondition {
      condition     = (var.edition == "ENTERPRISE_PLUS") == startswith(local.tier, "db-perf-optimized-N-")
      error_message = "tier \"${local.tier}\" does not match edition \"${var.edition}\" (ENTERPRISE_PLUS requires db-perf-optimized-N-* tiers; ENTERPRISE uses db-custom-* or standard tiers)."
    }
  }
}

resource "google_sql_database_instance" "read_replica" {
  for_each = local.replica_configs

  name                 = each.value.name
  master_instance_name = google_sql_database_instance.primary.name
  database_version     = var.database_version
  region               = each.value.region
  encryption_key_name  = each.value.encryption_key_name
  deletion_protection  = each.value.deletion_protection

  settings {
    edition                     = var.edition
    tier                        = each.value.tier
    availability_type           = each.value.availability_type
    disk_type                   = each.value.disk_type
    disk_autoresize             = true
    disk_autoresize_limit       = each.value.disk_autoresize_limit
    deletion_protection_enabled = each.value.deletion_protection
    connector_enforcement       = var.connector_enforcement
    user_labels                 = each.value.labels

    ip_configuration {
      ipv4_enabled                                  = false
      private_network                               = data.google_compute_network.vpc.id
      allocated_ip_range                            = var.allocated_ip_range
      ssl_mode                                      = "ENCRYPTED_ONLY"
      enable_private_path_for_google_cloud_services = true
    }

    dynamic "location_preference" {
      for_each = each.value.zone != null ? [1] : []
      content {
        zone = each.value.zone
      }
    }

    insights_config {
      query_insights_enabled  = true
      query_string_length     = var.query_insights.query_string_length
      record_application_tags = true
      record_client_address   = true
      query_plans_per_minute  = var.query_insights.query_plans_per_minute
    }

    dynamic "data_cache_config" {
      for_each = var.edition == "ENTERPRISE_PLUS" ? [1] : []
      content {
        data_cache_enabled = var.data_cache_enabled
      }
    }

    dynamic "database_flags" {
      for_each = each.value.database_flags
      content {
        name  = database_flags.key
        value = database_flags.value
      }
    }
  }

  lifecycle {
    precondition {
      condition     = (var.edition == "ENTERPRISE_PLUS") == startswith(each.value.tier, "db-perf-optimized-N-")
      error_message = "Read replica \"${each.key}\" tier \"${each.value.tier}\" does not match edition \"${var.edition}\"."
    }
  }
}

resource "google_sql_database" "databases" {
  for_each = var.databases

  name            = each.key
  instance        = google_sql_database_instance.primary.name
  charset         = each.value.charset
  collation       = each.value.collation
  deletion_policy = each.value.deletion_policy
}
