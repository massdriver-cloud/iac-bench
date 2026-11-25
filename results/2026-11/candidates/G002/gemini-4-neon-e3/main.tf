data "google_client_config" "current" {}

data "google_compute_network" "vpc" {
  name    = local.vpc_network_name
  project = local.project_id
}

resource "google_sql_database_instance" "primary" {
  name                = var.name
  project             = local.project_id
  region              = local.region
  database_version    = var.database_version
  deletion_protection = local.deletion_protection
  encryption_key_name = var.encryption_key_name

  settings {
    tier                        = var.tier
    edition                     = var.edition
    availability_type           = local.availability_type
    disk_type                   = var.disk_type
    disk_size                   = var.disk_size_gb
    disk_autoresize             = true
    disk_autoresize_limit       = var.disk_autoresize_limit_gb
    deletion_protection_enabled = local.deletion_protection
    retain_backups_on_delete    = true
    connector_enforcement       = var.connector_enforcement
    user_labels                 = local.primary_labels

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
      transaction_log_retention_days = local.transaction_log_retention_days

      backup_retention_settings {
        retained_backups = local.retained_backups
        retention_unit   = "COUNT"
      }
    }

    insights_config {
      query_insights_enabled  = true
      query_string_length     = var.query_insights.query_string_length
      query_plans_per_minute  = var.query_insights.query_plans_per_minute
      record_application_tags = var.query_insights.record_application_tags
      record_client_address   = var.query_insights.record_client_address
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

    dynamic "data_cache_config" {
      for_each = var.edition == "ENTERPRISE_PLUS" ? [1] : []
      content {
        data_cache_enabled = var.data_cache_enabled
      }
    }

    # Defense-in-depth: even though access is standardized on Google IAM
    # identities, enforce strong password rules if a break-glass password is set.
    password_validation_policy {
      enable_password_policy      = true
      min_length                  = 16
      complexity                  = "COMPLEXITY_DEFAULT"
      reuse_interval              = 5
      disallow_username_substring = true
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
    ignore_changes = [
      settings[0].disk_size,
    ]

    precondition {
      condition     = local.region != ""
      error_message = "A GCP region must be specified via var.region or the Google provider configuration."
    }

    precondition {
      condition     = !var.data_cache_enabled || var.edition == "ENTERPRISE_PLUS"
      error_message = "data_cache_enabled requires edition = ENTERPRISE_PLUS."
    }

    precondition {
      condition     = !startswith(var.tier, "db-perf-optimized-") || var.edition == "ENTERPRISE_PLUS"
      error_message = "db-perf-optimized-* tiers require edition = ENTERPRISE_PLUS."
    }

    precondition {
      condition     = !(contains(["db-f1-micro", "db-g1-small"], var.tier) && local.availability_type == "REGIONAL")
      error_message = "Shared-core tiers (db-f1-micro, db-g1-small) do not support REGIONAL high availability."
    }

    precondition {
      condition     = var.edition == "ENTERPRISE_PLUS" || local.transaction_log_retention_days <= 7
      error_message = "transaction_log_retention_days cannot exceed 7 when edition is ENTERPRISE (max 35 for ENTERPRISE_PLUS)."
    }

    precondition {
      condition     = var.disk_autoresize_limit_gb == 0 || var.disk_autoresize_limit_gb >= var.disk_size_gb
      error_message = "disk_autoresize_limit_gb must be 0 (unlimited) or greater than or equal to disk_size_gb."
    }

    precondition {
      condition     = var.secondary_zone == null || local.availability_type == "REGIONAL"
      error_message = "secondary_zone can only be set when availability_type is REGIONAL."
    }
  }
}

resource "google_sql_database" "this" {
  for_each = var.databases

  name            = each.key
  project         = local.project_id
  instance        = google_sql_database_instance.primary.name
  charset         = each.value.charset
  collation       = each.value.collation
  deletion_policy = each.value.deletion_policy
}

resource "google_sql_user" "iam_user" {
  for_each = var.iam_users

  name     = each.value
  project  = local.project_id
  instance = google_sql_database_instance.primary.name
  type     = "CLOUD_IAM_USER"
}

resource "google_sql_user" "iam_service_account" {
  for_each = local.iam_service_account_usernames

  name     = each.value
  project  = local.project_id
  instance = google_sql_database_instance.primary.name
  type     = "CLOUD_IAM_SERVICE_ACCOUNT"
}

resource "google_sql_user" "iam_group" {
  for_each = var.iam_groups

  name     = each.value
  project  = local.project_id
  instance = google_sql_database_instance.primary.name
  type     = "CLOUD_IAM_GROUP"
}

resource "google_project_iam_member" "cloudsql_access" {
  for_each = local.project_iam_bindings

  project = local.project_id
  role    = each.value.role
  member  = each.value.member
}
