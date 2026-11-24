data "google_client_config" "current" {}

data "google_compute_network" "vpc" {
  name = local.vpc_network_name
}

resource "google_sql_database_instance" "primary" {
  name                = local.instance_name
  database_version    = var.database_version
  region              = local.region
  deletion_protection = local.deletion_protection
  encryption_key_name = var.kms_key_name

  lifecycle {
    precondition {
      condition     = var.edition == "ENTERPRISE_PLUS" ? local.pitr_retention_days <= 35 : local.pitr_retention_days <= 7
      error_message = "ENTERPRISE edition supports pitr_retention_days up to 7; use ENTERPRISE_PLUS for up to 35 days."
    }

    precondition {
      condition     = var.disk_autoresize_limit == 0 || var.disk_autoresize_limit >= var.disk_size
      error_message = "disk_autoresize_limit must be 0 (unlimited) or >= disk_size."
    }
  }

  settings {
    tier                  = var.tier
    edition               = var.edition
    availability_type     = local.availability_type
    disk_type             = var.disk_type
    disk_size             = var.disk_size
    disk_autoresize       = true
    disk_autoresize_limit = var.disk_autoresize_limit
    user_labels           = local.primary_labels

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
      point_in_time_recovery_enabled = true
      transaction_log_retention_days = local.pitr_retention_days

      backup_retention_settings {
        retained_backups = local.backup_retention_count
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
      query_plans_per_minute  = 5
      query_string_length     = 4096
      record_application_tags = true
      record_client_address   = true
    }

    dynamic "location_preference" {
      for_each = var.zone != null || var.secondary_zone != null ? [1] : []
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
}

resource "google_sql_database_instance" "read_replicas" {
  for_each = var.read_replicas

  name                 = "${local.instance_name}-rr-${each.key}"
  master_instance_name = google_sql_database_instance.primary.name
  database_version     = var.database_version
  region               = coalesce(each.value.region, local.region)
  deletion_protection  = coalesce(each.value.deletion_protection, local.deletion_protection)
  encryption_key_name  = var.kms_key_name

  settings {
    tier                  = coalesce(each.value.tier, var.tier)
    edition               = var.edition
    availability_type     = coalesce(each.value.availability_type, "ZONAL")
    disk_type             = coalesce(each.value.disk_type, var.disk_type)
    disk_size             = coalesce(each.value.disk_size, var.disk_size)
    disk_autoresize       = true
    disk_autoresize_limit = coalesce(each.value.disk_autoresize_limit, var.disk_autoresize_limit)

    user_labels = merge(
      var.labels,
      each.value.labels,
      local.standard_labels,
      {
        instance_role = "read-replica"
      }
    )

    ip_configuration {
      ipv4_enabled                                  = false
      private_network                               = data.google_compute_network.vpc.id
      allocated_ip_range                            = var.allocated_ip_range
      enable_private_path_for_google_cloud_services = true
      ssl_mode                                      = "ENCRYPTED_ONLY"
    }

    insights_config {
      query_insights_enabled  = true
      query_plans_per_minute  = 5
      query_string_length     = 4096
      record_application_tags = true
      record_client_address   = true
    }

    dynamic "location_preference" {
      for_each = each.value.zone != null ? [1] : []
      content {
        zone = each.value.zone
      }
    }

    dynamic "database_flags" {
      for_each = merge(local.default_database_flags, each.value.database_flags, local.mandatory_database_flags)
      content {
        name  = database_flags.key
        value = database_flags.value
      }
    }
  }
}

resource "google_sql_database" "databases" {
  for_each = var.databases

  name      = each.key
  instance  = google_sql_database_instance.primary.name
  charset   = each.value.charset
  collation = each.value.collation
}
