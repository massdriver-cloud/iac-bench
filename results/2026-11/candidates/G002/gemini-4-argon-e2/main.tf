locals {
  vpc_network_name = "apps-${var.environment}"

  availability_type   = coalesce(var.availability_type, var.environment == "prod" ? "REGIONAL" : "ZONAL")
  deletion_protection = coalesce(var.deletion_protection, var.environment == "prod" ? true : false)

  # Standard baseline PostgreSQL flags for IAM auth and security/DBA auditing.
  # DBAs can override tuning flags or add custom flags via var.database_flags,
  # while cloudsql.iam_authentication is guaranteed to remain "on".
  default_database_flags = {
    "cloudsql.iam_authentication" = "on"
    "cloudsql.enable_pgaudit"     = "on"
    "pgaudit.log"                 = "read,write,ddl,role"
    "log_connections"             = "on"
    "log_disconnections"          = "on"
    "log_lock_waits"              = "on"
    "log_temp_files"              = "0"
    "log_min_duration_statement"  = "1000"
  }

  effective_database_flags = merge(
    local.default_database_flags,
    var.database_flags,
    {
      "cloudsql.iam_authentication" = "on"
    }
  )

  default_labels = {
    managed_by  = "opentofu"
    environment = var.environment
    instance    = var.instance_name
  }

  effective_labels = merge(local.default_labels, var.labels)

  # For CLOUD_IAM_SERVICE_ACCOUNT on PostgreSQL, Cloud SQL requires the ".gserviceaccount.com"
  # suffix to be stripped from the database username.
  normalized_iam_users = {
    for k, u in var.iam_users : k => {
      name = u.type == "CLOUD_IAM_SERVICE_ACCOUNT" ? trimsuffix(u.name, ".gserviceaccount.com") : u.name
      type = u.type
    }
  }
}

data "google_compute_network" "vpc" {
  name = local.vpc_network_name
}

resource "google_sql_database_instance" "postgresql" {
  name                = var.instance_name
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
    disk_autoresize_limit       = var.disk_autoresize_limit
    deletion_protection_enabled = local.deletion_protection
    user_labels                 = local.effective_labels

    ip_configuration {
      ipv4_enabled                                  = false
      private_network                               = data.google_compute_network.vpc.id
      enable_private_path_for_google_cloud_services = true
      ssl_mode                                      = "ENCRYPTED_ONLY"
    }

    backup_configuration {
      enabled                        = true
      start_time                     = var.backup_config.start_time
      location                       = var.backup_config.location
      point_in_time_recovery_enabled = var.backup_config.point_in_time_recovery_enabled
      transaction_log_retention_days = var.backup_config.transaction_log_retention_days

      backup_retention_settings {
        retained_backups = var.backup_config.retained_backups
        retention_unit   = "COUNT"
      }
    }

    maintenance_window {
      day          = var.maintenance_window.day
      hour         = var.maintenance_window.hour
      update_track = var.maintenance_window.update_track
    }

    insights_config {
      query_insights_enabled  = var.insights_config.query_insights_enabled
      query_string_length     = var.insights_config.query_string_length
      record_application_tags = var.insights_config.record_application_tags
      record_client_address   = var.insights_config.record_client_address
      query_plans_per_minute  = var.insights_config.query_plans_per_minute
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

  name            = each.key
  instance        = google_sql_database_instance.postgresql.name
  charset         = each.value.charset
  collation       = each.value.collation
  deletion_policy = each.value.deletion_policy
}

resource "google_sql_user" "iam_users" {
  for_each = local.normalized_iam_users

  instance = google_sql_database_instance.postgresql.name
  name     = each.value.name
  type     = each.value.type
}
