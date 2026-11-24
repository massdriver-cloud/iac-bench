data "google_client_config" "current" {}

resource "google_sql_database_instance" "primary" {
  name                = local.instance_name
  project             = local.project_id
  region              = local.region
  database_version    = var.database_version
  encryption_key_name = var.encryption_key_name
  deletion_protection = local.deletion_protection

  settings {
    tier                        = var.tier
    edition                     = var.edition
    availability_type           = local.availability_type
    activation_policy           = "ALWAYS"
    deletion_protection_enabled = local.deletion_protection
    connector_enforcement       = var.connector_enforcement

    disk_type                        = var.disk_type
    disk_size                        = var.disk_size_gb
    disk_autoresize                  = var.disk_autoresize
    disk_autoresize_limit            = var.disk_autoresize_limit_gb
    data_disk_provisioned_iops       = var.provisioned_iops
    data_disk_provisioned_throughput = var.provisioned_throughput_mbps

    user_labels = local.primary_labels

    ip_configuration {
      ipv4_enabled                                  = false
      private_network                               = local.vpc_network_id
      allocated_ip_range                            = var.allocated_ip_range
      ssl_mode                                      = var.ssl_mode
      enable_private_path_for_google_cloud_services = true
    }

    backup_configuration {
      enabled                        = true
      start_time                     = var.backup_configuration.start_time
      location                       = var.backup_configuration.location
      point_in_time_recovery_enabled = local.pitr_enabled
      transaction_log_retention_days = local.transaction_log_retention_days

      backup_retention_settings {
        retained_backups = local.retained_backups
        retention_unit   = "COUNT"
      }
    }

    maintenance_window {
      day          = var.maintenance_window.day
      hour         = var.maintenance_window.hour
      update_track = var.maintenance_window.update_track
    }

    insights_config {
      query_insights_enabled  = var.insights_config.enabled
      query_plans_per_minute  = var.insights_config.query_plans_per_minute
      query_string_length     = var.insights_config.query_string_length
      record_application_tags = var.insights_config.record_application_tags
      record_client_address   = var.insights_config.record_client_address
    }

    dynamic "location_preference" {
      for_each = var.zone != null || var.secondary_zone != null ? [1] : []
      content {
        zone           = var.zone
        secondary_zone = var.secondary_zone
      }
    }

    dynamic "data_cache_config" {
      for_each = var.edition == "ENTERPRISE_PLUS" ? [1] : []
      content {
        data_cache_enabled = var.data_cache_enabled
      }
    }

    dynamic "connection_pool_config" {
      for_each = var.managed_connection_pooling_enabled ? [1] : []
      content {
        connection_pooling_enabled = true
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
    precondition {
      condition     = local.project_id != null && local.project_id != ""
      error_message = "The Google provider must be configured with a target project."
    }

    precondition {
      condition     = local.region != null && local.region != ""
      error_message = "A region must be configured either on the Google provider or via var.region."
    }

    precondition {
      condition     = local.availability_type != "REGIONAL" || local.pitr_enabled
      error_message = "REGIONAL high availability in Cloud SQL for PostgreSQL requires backup_configuration.point_in_time_recovery_enabled = true."
    }

    precondition {
      condition     = !var.data_cache_enabled || var.edition == "ENTERPRISE_PLUS"
      error_message = "data_cache_enabled = true requires edition = 'ENTERPRISE_PLUS'."
    }

    precondition {
      condition     = !var.managed_connection_pooling_enabled || var.edition == "ENTERPRISE_PLUS"
      error_message = "managed_connection_pooling_enabled = true requires edition = 'ENTERPRISE_PLUS'."
    }

    precondition {
      condition     = var.edition != "ENTERPRISE_PLUS" || !contains(["db-f1-micro", "db-g1-small"], var.tier)
      error_message = "Shared-core tiers ('db-f1-micro', 'db-g1-small') are not supported with edition = 'ENTERPRISE_PLUS'."
    }

    precondition {
      condition     = var.edition == "ENTERPRISE_PLUS" || local.transaction_log_retention_days <= 7
      error_message = "transaction_log_retention_days > 7 requires edition = 'ENTERPRISE_PLUS' (ENTERPRISE supports 1..7 days)."
    }

    precondition {
      condition     = var.disk_autoresize_limit_gb == 0 || var.disk_autoresize_limit_gb >= var.disk_size_gb
      error_message = "disk_autoresize_limit_gb must be 0 (unlimited) or greater than or equal to disk_size_gb."
    }

    precondition {
      condition     = var.secondary_zone == null || local.availability_type == "REGIONAL"
      error_message = "secondary_zone can only be set when availability_type is 'REGIONAL'."
    }

    precondition {
      condition = (
        (var.zone == null || startswith(var.zone, "${local.region}-")) &&
        (var.secondary_zone == null || startswith(var.secondary_zone, "${local.region}-")) &&
        (var.zone == null || var.secondary_zone == null || var.zone != var.secondary_zone)
      )
      error_message = "zone and secondary_zone must belong to the primary instance region and must be distinct zones."
    }
  }
}

resource "google_sql_database_instance" "read_replica" {
  for_each = var.read_replicas

  name                 = "${local.instance_name}-replica-${each.key}"
  project              = local.project_id
  region               = each.value.region != null ? each.value.region : local.region
  database_version     = var.database_version
  master_instance_name = google_sql_database_instance.primary.name
  deletion_protection  = each.value.deletion_protection != null ? each.value.deletion_protection : local.deletion_protection

  encryption_key_name = (
    each.value.encryption_key_name != null
    ? each.value.encryption_key_name
    : (each.value.region == null || each.value.region == local.region ? var.encryption_key_name : null)
  )

  settings {
    tier                        = each.value.tier != null ? each.value.tier : var.tier
    edition                     = var.edition
    availability_type           = each.value.availability_type
    activation_policy           = "ALWAYS"
    deletion_protection_enabled = each.value.deletion_protection != null ? each.value.deletion_protection : local.deletion_protection
    connector_enforcement       = var.connector_enforcement

    disk_type             = each.value.disk_type != null ? each.value.disk_type : var.disk_type
    disk_size             = each.value.disk_size_gb != null ? each.value.disk_size_gb : var.disk_size_gb
    disk_autoresize       = var.disk_autoresize
    disk_autoresize_limit = var.disk_autoresize_limit_gb

    user_labels = merge(local.base_labels, {
      instance_role = "replica"
      replica_key   = each.key
    })

    ip_configuration {
      ipv4_enabled                                  = false
      private_network                               = local.vpc_network_id
      allocated_ip_range                            = each.value.allocated_ip_range != null ? each.value.allocated_ip_range : var.allocated_ip_range
      ssl_mode                                      = var.ssl_mode
      enable_private_path_for_google_cloud_services = true
    }

    insights_config {
      query_insights_enabled  = var.insights_config.enabled
      query_plans_per_minute  = var.insights_config.query_plans_per_minute
      query_string_length     = var.insights_config.query_string_length
      record_application_tags = var.insights_config.record_application_tags
      record_client_address   = var.insights_config.record_client_address
    }

    dynamic "location_preference" {
      for_each = each.value.zone != null ? [1] : []
      content {
        zone = each.value.zone
      }
    }

    dynamic "data_cache_config" {
      for_each = var.edition == "ENTERPRISE_PLUS" ? [1] : []
      content {
        data_cache_enabled = var.data_cache_enabled
      }
    }

    dynamic "connection_pool_config" {
      for_each = var.managed_connection_pooling_enabled ? [1] : []
      content {
        connection_pooling_enabled = true
      }
    }

    dynamic "database_flags" {
      for_each = local.replica_database_flags[each.key]
      content {
        name  = database_flags.key
        value = database_flags.value
      }
    }
  }

  lifecycle {
    precondition {
      condition     = each.value.zone == null || startswith(each.value.zone, "${each.value.region != null ? each.value.region : local.region}-")
      error_message = "Read replica zone must belong to the replica's target region."
    }

    precondition {
      condition     = var.edition != "ENTERPRISE_PLUS" || !contains(["db-f1-micro", "db-g1-small"], each.value.tier != null ? each.value.tier : var.tier)
      error_message = "Shared-core tiers ('db-f1-micro', 'db-g1-small') are not supported on read replicas when edition = 'ENTERPRISE_PLUS'."
    }
  }
}

resource "google_sql_database" "database" {
  for_each = var.databases

  name            = each.key
  project         = local.project_id
  instance        = google_sql_database_instance.primary.name
  charset         = each.value.charset
  collation       = each.value.collation
  deletion_policy = each.value.deletion_policy
}
