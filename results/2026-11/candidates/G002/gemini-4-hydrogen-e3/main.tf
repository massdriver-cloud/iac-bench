resource "google_sql_database_instance" "primary" {
  name                = local.instance_name
  region              = var.region
  database_version    = var.database_version
  deletion_protection = local.deletion_protection
  encryption_key_name = var.cmek_key_name

  settings {
    tier                        = local.tier
    edition                     = var.edition
    availability_type           = local.availability_type
    disk_size                   = local.disk_size
    disk_type                   = var.disk_type
    disk_autoresize             = var.disk_autoresize
    disk_autoresize_limit       = var.disk_autoresize_limit
    deletion_protection_enabled = local.deletion_protection
    user_labels                 = local.labels

    ip_configuration {
      ipv4_enabled                                  = false
      private_network                               = data.google_compute_network.vpc.id
      enable_private_path_for_google_cloud_services = true
      ssl_mode                                      = "ENCRYPTED_ONLY"
    }

    backup_configuration {
      enabled                        = true
      start_time                     = var.backup_start_time
      point_in_time_recovery_enabled = true
      transaction_log_retention_days = var.transaction_log_retention_days

      backup_retention_settings {
        retained_backups = local.retained_backups
        retention_unit   = "COUNT"
      }
    }

    maintenance_window {
      day          = var.maintenance_window_day
      hour         = var.maintenance_window_hour
      update_track = local.maintenance_update_track
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
      query_plans_per_minute  = var.insights_query_plans_per_minute
      query_string_length     = var.insights_query_string_length
      record_application_tags = true
      record_client_address   = true
    }

    dynamic "data_cache_config" {
      for_each = var.edition == "ENTERPRISE_PLUS" && var.data_cache_enabled ? [1] : []
      content {
        data_cache_enabled = true
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
}

resource "google_sql_database" "databases" {
  for_each = var.databases

  name      = each.key
  instance  = google_sql_database_instance.primary.name
  charset   = each.value.charset
  collation = each.value.collation
}

resource "google_sql_user" "iam_users" {
  for_each = local.iam_principals

  name     = each.value.sql_name
  instance = google_sql_database_instance.primary.name
  type     = each.value.sql_type
}

resource "google_project_iam_member" "cloudsql_access" {
  for_each = local.iam_role_bindings

  project = data.google_client_config.current.project
  role    = each.value.role
  member  = each.value.member

  condition {
    title       = "cloudsql-instance-${local.instance_name}"
    description = "Scope Cloud SQL IAM access to instance ${local.instance_name} and its replicas"
    expression  = local.iam_condition_expression
  }

  depends_on = [
    google_sql_database_instance.primary,
    google_sql_database_instance.read_replicas,
  ]
}

resource "google_sql_database_instance" "read_replicas" {
  for_each = var.read_replicas

  name                 = "${local.instance_name}-${each.key}"
  master_instance_name = google_sql_database_instance.primary.name
  region               = coalesce(each.value.region, var.region)
  database_version     = var.database_version
  deletion_protection  = local.deletion_protection
  encryption_key_name  = var.cmek_key_name

  replica_configuration {
    failover_target = false
  }

  settings {
    tier                        = coalesce(each.value.tier, local.tier)
    edition                     = var.edition
    availability_type           = each.value.availability_type
    disk_size                   = coalesce(each.value.disk_size, local.disk_size)
    disk_type                   = var.disk_type
    disk_autoresize             = var.disk_autoresize
    disk_autoresize_limit       = var.disk_autoresize_limit
    deletion_protection_enabled = local.deletion_protection
    user_labels                 = merge(local.labels, { role = "read-replica" })

    ip_configuration {
      ipv4_enabled                                  = false
      private_network                               = data.google_compute_network.vpc.id
      enable_private_path_for_google_cloud_services = true
      ssl_mode                                      = "ENCRYPTED_ONLY"
    }

    dynamic "location_preference" {
      for_each = each.value.zone != null ? [1] : []
      content {
        zone = each.value.zone
      }
    }

    insights_config {
      query_insights_enabled  = true
      query_plans_per_minute  = var.insights_query_plans_per_minute
      query_string_length     = var.insights_query_string_length
      record_application_tags = true
      record_client_address   = true
    }

    dynamic "database_flags" {
      for_each = merge(local.default_database_flags, var.database_flags, each.value.database_flags, local.enforced_database_flags)
      content {
        name  = database_flags.key
        value = database_flags.value
      }
    }
  }
}
