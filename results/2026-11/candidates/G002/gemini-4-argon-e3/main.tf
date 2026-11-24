locals {
  project_id   = data.google_client_config.current.project
  network_name = "apps-${var.environment}"
  network_id   = "projects/${local.project_id}/global/networks/${local.network_name}"

  availability_type   = coalesce(var.availability_type, var.environment == "prod" ? "REGIONAL" : "ZONAL")
  deletion_protection = var.deletion_protection != null ? var.deletion_protection : (var.environment == "prod" ? true : false)

  # Standard baseline PostgreSQL flags for IAM auth, auditing, and DBA observability.
  # DBAs can override tuning/logging flags via var.database_flags, while IAM authentication is always enforced.
  default_database_flags = {
    "cloudsql.iam_authentication" = "on"
    "cloudsql.enable_pgaudit"     = "on"
    "pgaudit.log"                 = "ddl,role"
    "log_connections"             = "on"
    "log_disconnections"          = "on"
    "log_checkpoints"             = "on"
    "log_lock_waits"              = "on"
    "log_temp_files"              = "0"
    "log_min_duration_statement"  = "1000"
  }

  merged_database_flags = merge(
    local.default_database_flags,
    var.database_flags,
    {
      "cloudsql.iam_authentication" = "on"
    }
  )

  standard_labels = merge(
    var.labels,
    {
      environment = var.environment
      managed_by  = "opentofu"
      instance    = var.instance_name
    }
  )
}

resource "google_sql_database_instance" "this" {
  name                = var.instance_name
  project             = local.project_id
  region              = var.region
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
    user_labels                 = local.standard_labels

    ip_configuration {
      ipv4_enabled                                  = false
      private_network                               = local.network_id
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
      query_insights_enabled  = var.insights_config.query_insights_enabled
      query_string_length     = var.insights_config.query_string_length
      record_application_tags = var.insights_config.record_application_tags
      record_client_address   = var.insights_config.record_client_address
      query_plans_per_minute  = var.insights_config.query_plans_per_minute
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

  name            = each.key
  instance        = google_sql_database_instance.this.name
  project         = local.project_id
  charset         = each.value.charset
  collation       = each.value.collation
  deletion_policy = each.value.deletion_policy
}

resource "google_sql_user" "iam_users" {
  for_each = var.iam_users

  name = (
    each.value.type == "CLOUD_IAM_SERVICE_ACCOUNT"
    ? trimsuffix(each.value.email, ".gserviceaccount.com")
    : each.value.email
  )
  instance        = google_sql_database_instance.this.name
  project         = local.project_id
  type            = each.value.type
  deletion_policy = each.value.deletion_policy
}
