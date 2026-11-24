data "google_client_config" "current" {}

locals {
  project_id    = data.google_client_config.current.project
  instance_name = "${var.name}-${var.environment}"

  # Network mapping per environment owned by the network team with Private Services Access pre-configured
  vpc_network_name      = "apps-${var.environment}"
  vpc_network_self_link = "projects/${local.project_id}/global/networks/${local.vpc_network_name}"

  # Environment-aware defaults when not explicitly overridden by the DBA
  availability_type   = coalesce(var.availability_type, var.environment == "prod" ? "REGIONAL" : "ZONAL")
  deletion_protection = var.deletion_protection != null ? var.deletion_protection : (var.environment == "prod")

  # Standard baseline flags enforced across every PostgreSQL instance:
  # - IAM authentication required so engineers and workloads authenticate via Google identity
  # - pgaudit and connection/disconnection logging enabled so security team can audit access by identity
  baseline_database_flags = {
    "cloudsql.iam_authentication" = "on"
    "cloudsql.enable_pgaudit"     = "on"
    "pgaudit.log"                 = "all"
    "log_connections"             = "on"
    "log_disconnections"          = "on"
    "log_checkpoints"             = "on"
    "log_lock_waits"              = "on"
    "log_temp_files"              = "0"
    "log_min_duration_statement"  = "1000"
  }

  # Merge DBA-supplied flags with baseline flags, ensuring critical security/audit flags stay enabled
  merged_database_flags = merge(
    local.baseline_database_flags,
    var.database_flags,
    {
      "cloudsql.iam_authentication" = "on"
      "cloudsql.enable_pgaudit"     = "on"
    }
  )

  common_labels = merge(
    var.labels,
    {
      environment = var.environment
      managed_by  = "opentofu"
      component   = "postgresql"
    }
  )
}

resource "google_sql_database_instance" "primary" {
  name                = local.instance_name
  project             = local.project_id
  region              = var.region
  database_version    = var.database_version
  encryption_key_name = var.kms_key_name
  deletion_protection = local.deletion_protection

  settings {
    tier                        = var.tier
    edition                     = var.edition
    availability_type           = local.availability_type
    disk_type                   = var.disk_type
    disk_size                   = var.disk_size_gb
    disk_autoresize             = true
    disk_autoresize_limit       = var.disk_autoresize_limit_gb
    deletion_protection_enabled = local.deletion_protection

    user_labels = local.common_labels

    ip_configuration {
      ipv4_enabled                                  = false
      private_network                               = local.vpc_network_self_link
      enable_private_path_for_google_cloud_services = true
      ssl_mode                                      = "ENCRYPTED_ONLY"
    }

    backup_configuration {
      enabled                        = true
      start_time                     = var.backup_configuration.start_time
      location                       = var.backup_configuration.location
      point_in_time_recovery_enabled = var.backup_configuration.point_in_time_recovery_enabled
      transaction_log_retention_days = var.backup_configuration.transaction_log_retention_days

      backup_retention_settings {
        retained_backups = var.backup_configuration.retained_backups
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
      query_plans_per_minute  = var.query_insights_config.query_plans_per_minute
      query_string_length     = var.query_insights_config.query_string_length
      record_application_tags = var.query_insights_config.record_application_tags
      record_client_address   = var.query_insights_config.record_client_address
    }

    dynamic "database_flags" {
      for_each = local.merged_database_flags
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
  project   = local.project_id
  charset   = each.value.charset
  collation = each.value.collation
}

resource "google_sql_user" "iam_users" {
  for_each = var.iam_users

  # Cloud SQL PostgreSQL expects service account usernames without the '.gserviceaccount.com' suffix
  name = (
    each.value.type == "CLOUD_IAM_SERVICE_ACCOUNT"
    ? trimsuffix(each.value.email, ".gserviceaccount.com")
    : each.value.email
  )
  instance = google_sql_database_instance.primary.name
  project  = local.project_id
  type     = each.value.type
}

resource "google_sql_database_instance" "read_replicas" {
  for_each = var.read_replicas

  name                 = "${local.instance_name}-replica-${each.key}"
  project              = local.project_id
  region               = coalesce(each.value.region, var.region)
  database_version     = var.database_version
  master_instance_name = google_sql_database_instance.primary.name
  encryption_key_name  = var.kms_key_name
  deletion_protection  = local.deletion_protection

  replica_configuration {
    failover_target = false
  }

  settings {
    tier                        = coalesce(each.value.tier, var.tier)
    edition                     = var.edition
    availability_type           = each.value.availability_type
    disk_type                   = var.disk_type
    disk_size                   = coalesce(each.value.disk_size_gb, var.disk_size_gb)
    disk_autoresize             = true
    disk_autoresize_limit       = var.disk_autoresize_limit_gb
    deletion_protection_enabled = local.deletion_protection

    user_labels = merge(
      local.common_labels,
      {
        role    = "read-replica"
        replica = each.key
      }
    )

    ip_configuration {
      ipv4_enabled                                  = false
      private_network                               = local.vpc_network_self_link
      enable_private_path_for_google_cloud_services = true
      ssl_mode                                      = "ENCRYPTED_ONLY"
    }

    insights_config {
      query_insights_enabled  = true
      query_plans_per_minute  = var.query_insights_config.query_plans_per_minute
      query_string_length     = var.query_insights_config.query_string_length
      record_application_tags = var.query_insights_config.record_application_tags
      record_client_address   = var.query_insights_config.record_client_address
    }

    dynamic "database_flags" {
      for_each = merge(
        local.merged_database_flags,
        each.value.database_flags,
        {
          "cloudsql.iam_authentication" = "on"
          "cloudsql.enable_pgaudit"     = "on"
        }
      )
      content {
        name  = database_flags.key
        value = database_flags.value
      }
    }
  }
}
