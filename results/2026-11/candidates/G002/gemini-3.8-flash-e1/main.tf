resource "google_sql_database_instance" "primary" {
  name                = var.name
  project             = local.project_id
  region              = var.region
  database_version    = var.database_version
  deletion_protection = local.deletion_protection

  settings {
    tier                  = var.tier
    edition               = var.edition
    availability_type     = local.availability_type
    disk_size             = var.disk_size_gb
    disk_type             = var.disk_type
    disk_autoresize       = var.disk_autoresize
    disk_autoresize_limit = var.disk_autoresize_limit
    user_labels           = local.effective_labels

    dynamic "location_preference" {
      for_each = var.zone != null || var.secondary_zone != null ? [1] : []
      content {
        zone           = var.zone
        secondary_zone = var.secondary_zone
      }
    }

    ip_configuration {
      ipv4_enabled                                  = false
      private_network                               = local.network_link
      allocated_ip_range                            = var.allocated_ip_range
      enable_private_path_for_google_cloud_services = true
      ssl_mode                                      = "ENCRYPTED_ONLY"
    }

    backup_configuration {
      enabled                        = coalesce(var.backup_configuration.enabled, true)
      start_time                     = coalesce(var.backup_configuration.start_time, "03:00")
      point_in_time_recovery_enabled = coalesce(var.backup_configuration.point_in_time_recovery_enabled, true)
      transaction_log_retention_days = coalesce(var.backup_configuration.transaction_log_retention_days, 7)

      backup_retention_settings {
        retained_backups = coalesce(var.backup_configuration.retained_backups, 14)
        retention_unit   = "COUNT"
      }
    }

    maintenance_window {
      day          = coalesce(var.maintenance_window.day, 7)
      hour         = coalesce(var.maintenance_window.hour, 4)
      update_track = coalesce(var.maintenance_window.update_track, "stable")
    }

    insights_config {
      query_insights_enabled  = coalesce(var.insights_config.query_insights_enabled, true)
      query_string_length     = coalesce(var.insights_config.query_string_length, 1024)
      record_application_tags = coalesce(var.insights_config.record_application_tags, true)
      record_client_address   = coalesce(var.insights_config.record_client_address, true)
      query_plans_per_minute  = coalesce(var.insights_config.query_plans_per_minute, 5)
    }

    password_validation_policy {
      min_length                  = 14
      complexity                  = "COMPLEXITY_DEFAULT"
      reuse_interval              = 3
      disallow_username_substring = true
      enable_password_policy      = true
    }

    dynamic "database_flags" {
      for_each = local.effective_database_flags
      content {
        name  = database_flags.key
        value = tostring(database_flags.value)
      }
    }
  }
}

resource "google_sql_database" "databases" {
  for_each = local.normalized_databases

  name      = each.value.name
  instance  = google_sql_database_instance.primary.name
  project   = local.project_id
  charset   = each.value.charset
  collation = each.value.collation
}

resource "google_sql_user" "iam_users" {
  for_each = toset(var.iam_users)

  name     = each.value
  instance = google_sql_database_instance.primary.name
  project  = local.project_id
  type     = "CLOUD_IAM_USER"
}

resource "google_sql_user" "iam_service_accounts" {
  for_each = local.normalized_iam_service_accounts

  name     = each.value
  instance = google_sql_database_instance.primary.name
  project  = local.project_id
  type     = "CLOUD_IAM_SERVICE_ACCOUNT"
}

resource "google_sql_database_instance" "replicas" {
  for_each = var.read_replicas

  name                 = each.key
  project              = local.project_id
  region               = var.region
  database_version     = var.database_version
  master_instance_name = google_sql_database_instance.primary.name
  deletion_protection  = false

  settings {
    tier                  = coalesce(each.value.tier, var.tier)
    availability_type     = "ZONAL"
    disk_size             = coalesce(each.value.disk_size_gb, var.disk_size_gb)
    disk_type             = coalesce(each.value.disk_type, var.disk_type)
    disk_autoresize       = coalesce(each.value.disk_autoresize, var.disk_autoresize)
    disk_autoresize_limit = coalesce(each.value.disk_autoresize_limit, var.disk_autoresize_limit)
    user_labels           = local.effective_labels

    dynamic "location_preference" {
      for_each = each.value.zone != null ? [1] : []
      content {
        zone = each.value.zone
      }
    }

    ip_configuration {
      ipv4_enabled                                  = false
      private_network                               = local.network_link
      allocated_ip_range                            = var.allocated_ip_range
      enable_private_path_for_google_cloud_services = true
      ssl_mode                                      = "ENCRYPTED_ONLY"
    }

    insights_config {
      query_insights_enabled  = coalesce(var.insights_config.query_insights_enabled, true)
      query_string_length     = coalesce(var.insights_config.query_string_length, 1024)
      record_application_tags = coalesce(var.insights_config.record_application_tags, true)
      record_client_address   = coalesce(var.insights_config.record_client_address, true)
      query_plans_per_minute  = coalesce(var.insights_config.query_plans_per_minute, 5)
    }

    dynamic "database_flags" {
      for_each = merge(local.baseline_database_flags, coalesce(each.value.database_flags, {}))
      content {
        name  = database_flags.key
        value = tostring(database_flags.value)
      }
    }
  }
}
