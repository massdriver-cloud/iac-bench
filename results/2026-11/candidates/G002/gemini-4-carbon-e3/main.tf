data "google_client_config" "current" {}

data "google_compute_network" "vpc" {
  name    = local.network_name
  project = local.project_id
}

resource "google_sql_database_instance" "primary" {
  name                = local.instance_name
  project             = local.project_id
  region              = local.region
  database_version    = var.database_version
  deletion_protection = local.deletion_protection
  encryption_key_name = var.encryption_key_name

  settings {
    tier                        = var.tier
    edition                     = var.edition
    availability_type           = local.availability_type
    activation_policy           = "ALWAYS"
    deletion_protection_enabled = local.deletion_protection
    connector_enforcement       = var.connector_enforcement

    disk_type             = var.disk_type
    disk_size             = var.disk_size_gb
    disk_autoresize       = true
    disk_autoresize_limit = var.disk_autoresize_limit_gb

    user_labels = merge(local.effective_labels, {
      role = "primary"
    })

    ip_configuration {
      ipv4_enabled                                  = false
      private_network                               = data.google_compute_network.vpc.id
      enable_private_path_for_google_cloud_services = true
      ssl_mode                                      = var.ssl_mode
      allocated_ip_range                            = var.allocated_ip_range
    }

    backup_configuration {
      enabled                        = true
      start_time                     = var.backup_configuration.start_time
      location                       = var.backup_configuration.location
      point_in_time_recovery_enabled = local.point_in_time_recovery_enabled
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
      query_plans_per_minute  = var.query_insights.query_plans_per_minute
      query_string_length     = var.query_insights.query_string_length
      record_application_tags = true
      record_client_address   = true
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
      error_message = "A Google Cloud region must be configured either via var.region or on the Google provider."
    }

    precondition {
      condition = (
        (var.edition == "ENTERPRISE_PLUS" && startswith(var.tier, "db-perf-optimized-N-")) ||
        (var.edition == "ENTERPRISE" && !startswith(var.tier, "db-perf-optimized-N-"))
      )
      error_message = "ENTERPRISE_PLUS instances require a 'db-perf-optimized-N-*' tier, while ENTERPRISE instances require 'db-custom-*', 'db-f1-micro', or 'db-g1-small'."
    }

    precondition {
      condition     = !var.data_cache_enabled || var.edition == "ENTERPRISE_PLUS"
      error_message = "data_cache_enabled can only be true when edition is 'ENTERPRISE_PLUS'."
    }

    precondition {
      condition     = !(local.availability_type == "REGIONAL" && contains(["db-f1-micro", "db-g1-small"], var.tier))
      error_message = "REGIONAL high availability is not supported on shared-core tiers ('db-f1-micro' or 'db-g1-small')."
    }

    precondition {
      condition     = var.disk_autoresize_limit_gb == 0 || var.disk_autoresize_limit_gb >= var.disk_size_gb
      error_message = "disk_autoresize_limit_gb must be 0 (unlimited) or greater than or equal to disk_size_gb."
    }

    precondition {
      condition     = local.transaction_log_retention_days <= 7 || var.edition == "ENTERPRISE_PLUS"
      error_message = "transaction_log_retention_days above 7 requires edition = 'ENTERPRISE_PLUS'."
    }

    precondition {
      condition     = var.environment != "prod" || local.point_in_time_recovery_enabled
      error_message = "point_in_time_recovery_enabled cannot be disabled in 'prod'."
    }

    precondition {
      condition     = length(var.read_replicas) == 0 || local.point_in_time_recovery_enabled
      error_message = "point_in_time_recovery_enabled must be true when read_replicas are configured."
    }
  }
}

resource "google_sql_database_instance" "read_replica" {
  for_each = var.read_replicas

  name                 = local.replica_instance_names[each.key]
  project              = local.project_id
  region               = each.value.region != null ? each.value.region : local.region
  database_version     = var.database_version
  master_instance_name = google_sql_database_instance.primary.name
  deletion_protection  = local.deletion_protection
  encryption_key_name = (
    each.value.encryption_key_name != null
    ? each.value.encryption_key_name
    : ((each.value.region != null ? each.value.region : local.region) == local.region ? var.encryption_key_name : null)
  )

  settings {
    tier                        = each.value.tier != null ? each.value.tier : var.tier
    edition                     = var.edition
    availability_type           = each.value.availability_type
    activation_policy           = "ALWAYS"
    deletion_protection_enabled = local.deletion_protection
    connector_enforcement       = var.connector_enforcement

    disk_type             = each.value.disk_type != null ? each.value.disk_type : var.disk_type
    disk_size             = each.value.disk_size_gb != null ? each.value.disk_size_gb : var.disk_size_gb
    disk_autoresize       = true
    disk_autoresize_limit = each.value.disk_autoresize_limit_gb != null ? each.value.disk_autoresize_limit_gb : var.disk_autoresize_limit_gb

    user_labels = merge(local.effective_labels, {
      role    = "replica"
      replica = each.key
    })

    ip_configuration {
      ipv4_enabled                                  = false
      private_network                               = data.google_compute_network.vpc.id
      enable_private_path_for_google_cloud_services = true
      ssl_mode                                      = var.ssl_mode
      allocated_ip_range                            = each.value.allocated_ip_range != null ? each.value.allocated_ip_range : var.allocated_ip_range
    }

    insights_config {
      query_insights_enabled  = true
      query_plans_per_minute  = var.query_insights.query_plans_per_minute
      query_string_length     = var.query_insights.query_string_length
      record_application_tags = true
      record_client_address   = true
    }

    dynamic "data_cache_config" {
      for_each = var.edition == "ENTERPRISE_PLUS" ? [1] : []
      content {
        data_cache_enabled = each.value.data_cache_enabled != null ? each.value.data_cache_enabled : var.data_cache_enabled
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
      condition = (
        (var.edition == "ENTERPRISE_PLUS" && startswith(each.value.tier != null ? each.value.tier : var.tier, "db-perf-optimized-N-")) ||
        (var.edition == "ENTERPRISE" && !startswith(each.value.tier != null ? each.value.tier : var.tier, "db-perf-optimized-N-"))
      )
      error_message = "Read replica tier must match the primary instance edition ('db-perf-optimized-N-*' for ENTERPRISE_PLUS; 'db-custom-*', 'db-f1-micro', or 'db-g1-small' for ENTERPRISE)."
    }

    precondition {
      condition     = !(each.value.availability_type == "REGIONAL" && contains(["db-f1-micro", "db-g1-small"], each.value.tier != null ? each.value.tier : var.tier))
      error_message = "Read replica REGIONAL high availability is not supported on shared-core tiers ('db-f1-micro' or 'db-g1-small')."
    }

    precondition {
      condition     = !(each.value.data_cache_enabled == true && var.edition != "ENTERPRISE_PLUS")
      error_message = "Read replica data_cache_enabled can only be true when edition is 'ENTERPRISE_PLUS'."
    }

    precondition {
      condition     = (each.value.disk_size_gb != null ? each.value.disk_size_gb : var.disk_size_gb) >= var.disk_size_gb
      error_message = "Read replica disk_size_gb must be greater than or equal to the primary instance disk_size_gb."
    }

    precondition {
      condition = (
        (each.value.disk_autoresize_limit_gb != null ? each.value.disk_autoresize_limit_gb : var.disk_autoresize_limit_gb) == 0 ||
        (each.value.disk_autoresize_limit_gb != null ? each.value.disk_autoresize_limit_gb : var.disk_autoresize_limit_gb) >= (each.value.disk_size_gb != null ? each.value.disk_size_gb : var.disk_size_gb)
      )
      error_message = "Read replica disk_autoresize_limit_gb must be 0 (unlimited) or greater than or equal to the replica disk_size_gb."
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

resource "google_sql_user" "iam_user" {
  for_each = var.iam_users

  name            = each.value
  project         = local.project_id
  instance        = google_sql_database_instance.primary.name
  type            = "CLOUD_IAM_USER"
  deletion_policy = local.user_deletion_policy
}

resource "google_sql_user" "iam_service_account" {
  for_each = var.iam_service_accounts

  name            = trimsuffix(each.value, ".gserviceaccount.com")
  project         = local.project_id
  instance        = google_sql_database_instance.primary.name
  type            = "CLOUD_IAM_SERVICE_ACCOUNT"
  deletion_policy = local.user_deletion_policy
}

resource "google_sql_user" "iam_group" {
  for_each = var.iam_groups

  name            = each.value
  project         = local.project_id
  instance        = google_sql_database_instance.primary.name
  type            = "CLOUD_IAM_GROUP"
  deletion_policy = local.user_deletion_policy
}

resource "google_project_iam_member" "database_access" {
  for_each = local.iam_role_bindings

  project = local.project_id
  role    = each.value.role
  member  = each.value.member

  condition {
    title       = "cloudsql-${local.instance_name}"
    description = "Restrict Cloud SQL client and IAM database authentication access to ${local.instance_name} and its read replicas."
    expression  = local.iam_instance_condition_expression
  }
}
