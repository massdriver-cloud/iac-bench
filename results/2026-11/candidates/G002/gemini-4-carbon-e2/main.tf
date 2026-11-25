data "google_client_config" "current" {}

# -----------------------------------------------------------------------------
# Primary Cloud SQL for PostgreSQL Instance
# -----------------------------------------------------------------------------

resource "google_sql_database_instance" "primary" {
  name                = local.instance_name
  project             = local.project_id
  region              = local.region
  database_version    = var.database_version
  deletion_protection = var.deletion_protection
  encryption_key_name = var.encryption_key_name

  settings {
    edition                     = var.edition
    tier                        = var.tier
    availability_type           = local.availability_type
    disk_type                   = var.disk_type
    disk_size                   = var.disk_size_gb
    disk_autoresize             = var.disk_autoresize
    disk_autoresize_limit       = var.disk_autoresize_limit_gb
    deletion_protection_enabled = var.deletion_protection
    user_labels                 = merge(local.labels, { instance_role = "primary" })

    dynamic "data_cache_config" {
      for_each = var.edition == "ENTERPRISE_PLUS" ? [1] : []
      content {
        data_cache_enabled = var.enable_data_cache
      }
    }

    ip_configuration {
      ipv4_enabled                                  = false
      private_network                               = local.network_self_link
      allocated_ip_range                            = var.allocated_ip_range
      ssl_mode                                      = "ENCRYPTED_ONLY"
      enable_private_path_for_google_cloud_services = true
    }

    backup_configuration {
      enabled                        = true
      start_time                     = var.backup_configuration.start_time
      location                       = var.backup_configuration.location
      point_in_time_recovery_enabled = true
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
      query_insights_enabled  = true
      record_application_tags = true
      record_client_address   = true
      query_plans_per_minute  = var.insights_config.query_plans_per_minute
      query_string_length     = var.insights_config.query_string_length
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
      condition     = local.project_id != ""
      error_message = "The Google provider must be configured with a target project."
    }

    precondition {
      condition     = !var.enable_data_cache || var.edition == "ENTERPRISE_PLUS"
      error_message = "enable_data_cache = true is only supported when edition = 'ENTERPRISE_PLUS'."
    }

    precondition {
      condition     = var.disk_autoresize_limit_gb == 0 || var.disk_autoresize_limit_gb >= var.disk_size_gb
      error_message = "disk_autoresize_limit_gb must be 0 (unlimited) or greater than or equal to disk_size_gb."
    }

    precondition {
      condition     = var.edition == "ENTERPRISE_PLUS" || local.transaction_log_retention_days <= 7
      error_message = "transaction_log_retention_days above 7 requires edition = 'ENTERPRISE_PLUS'."
    }
  }
}

# -----------------------------------------------------------------------------
# Read Replicas
# -----------------------------------------------------------------------------

resource "google_sql_database_instance" "read_replica" {
  for_each = var.read_replicas

  name                 = "${local.instance_name}-replica-${each.key}"
  project              = local.project_id
  region               = coalesce(each.value.region, local.region)
  database_version     = var.database_version
  master_instance_name = google_sql_database_instance.primary.name
  deletion_protection  = var.deletion_protection
  encryption_key_name  = each.value.encryption_key_name

  settings {
    edition                     = var.edition
    tier                        = coalesce(each.value.tier, var.tier)
    availability_type           = each.value.availability_type
    disk_type                   = coalesce(each.value.disk_type, var.disk_type)
    disk_size                   = coalesce(each.value.disk_size_gb, var.disk_size_gb)
    disk_autoresize             = coalesce(each.value.disk_autoresize, var.disk_autoresize)
    disk_autoresize_limit       = coalesce(each.value.disk_autoresize_limit_gb, var.disk_autoresize_limit_gb)
    deletion_protection_enabled = var.deletion_protection
    user_labels                 = merge(local.labels, { instance_role = "read-replica" })

    dynamic "data_cache_config" {
      for_each = var.edition == "ENTERPRISE_PLUS" ? [1] : []
      content {
        data_cache_enabled = coalesce(each.value.enable_data_cache, var.enable_data_cache)
      }
    }

    ip_configuration {
      ipv4_enabled                                  = false
      private_network                               = local.network_self_link
      allocated_ip_range                            = var.allocated_ip_range
      ssl_mode                                      = "ENCRYPTED_ONLY"
      enable_private_path_for_google_cloud_services = true
    }

    insights_config {
      query_insights_enabled  = true
      record_application_tags = true
      record_client_address   = true
      query_plans_per_minute  = var.insights_config.query_plans_per_minute
      query_string_length     = var.insights_config.query_string_length
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
      condition     = each.value.enable_data_cache != true || var.edition == "ENTERPRISE_PLUS"
      error_message = "Read replica enable_data_cache = true is only supported when edition = 'ENTERPRISE_PLUS'."
    }
  }
}

# -----------------------------------------------------------------------------
# Logical PostgreSQL Databases
# -----------------------------------------------------------------------------

resource "google_sql_database" "database" {
  for_each = var.databases

  project         = local.project_id
  instance        = google_sql_database_instance.primary.name
  name            = each.key
  charset         = each.value.charset
  collation       = each.value.collation
  deletion_policy = each.value.deletion_policy
}

# -----------------------------------------------------------------------------
# Google IAM Database Users (Humans, Workloads, Groups)
# -----------------------------------------------------------------------------

resource "google_sql_user" "iam_user" {
  for_each = var.iam_users

  project         = local.project_id
  instance        = google_sql_database_instance.primary.name
  name            = each.value
  type            = "CLOUD_IAM_USER"
  deletion_policy = var.user_deletion_policy
}

resource "google_sql_user" "iam_service_account" {
  for_each = local.iam_service_account_db_users

  project         = local.project_id
  instance        = google_sql_database_instance.primary.name
  name            = each.value
  type            = "CLOUD_IAM_SERVICE_ACCOUNT"
  deletion_policy = var.user_deletion_policy
}

resource "google_sql_user" "iam_group" {
  for_each = var.iam_groups

  project         = local.project_id
  instance        = google_sql_database_instance.primary.name
  name            = each.value
  type            = "CLOUD_IAM_GROUP"
  deletion_policy = var.user_deletion_policy
}

# -----------------------------------------------------------------------------
# Instance-Scoped Cloud SQL IAM Bindings
# -----------------------------------------------------------------------------

resource "google_project_iam_member" "cloudsql_access" {
  for_each = local.iam_role_bindings

  project = local.project_id
  role    = each.value.role
  member  = each.value.member

  condition {
    title       = "cloudsql-${local.instance_name}"
    description = "Restrict Cloud SQL connectivity and IAM login to ${local.instance_name} and its read replicas."
    expression  = local.iam_condition_expression
  }

  depends_on = [google_sql_database_instance.primary]
}
