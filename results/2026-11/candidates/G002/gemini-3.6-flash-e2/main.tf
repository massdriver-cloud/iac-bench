locals {
  default_database_flags = [
    {
      name  = "cloudsql.iam_authentication"
      value = "on"
    }
  ]

  user_flag_names = [for flag in var.database_flags : flag.name]

  merged_database_flags = concat(
    [
      for flag in local.default_database_flags :
      flag if !contains(local.user_flag_names, flag.name)
    ],
    var.database_flags
  )
}

resource "google_sql_database_instance" "default" {
  name             = var.instance_name
  project          = var.project_id
  region           = var.region
  database_version = var.database_version

  settings {
    tier                  = var.tier
    availability_type     = var.availability_type
    disk_type             = var.disk_type
    disk_size             = var.disk_size
    disk_autoresize       = var.disk_autoresize
    disk_autoresize_limit = var.disk_autoresize_limit
    user_labels           = var.labels

    ip_configuration {
      ipv4_enabled                                  = var.ipv4_enabled
      private_network                               = var.private_network
      ssl_mode                                      = var.ssl_mode
      enable_private_path_for_google_cloud_services = var.enable_private_path
    }

    backup_configuration {
      enabled                        = var.backup_enabled
      start_time                     = var.backup_start_time
      location                       = var.region
      point_in_time_recovery_enabled = var.point_in_time_recovery_enabled
      transaction_log_retention_days = var.transaction_log_retention_days

      backup_retention_settings {
        retained_backups = var.retained_backups
        retention_unit   = "COUNT"
      }
    }

    maintenance_window {
      day          = var.maintenance_window_day
      hour         = var.maintenance_window_hour
      update_track = var.maintenance_window_update_track
    }

    insights_config {
      query_insights_enabled  = var.query_insights_enabled
      query_string_length     = var.query_string_length
      record_application_tags = var.record_application_tags
      record_client_address   = var.record_client_address
      query_plans_per_minute  = var.query_plans_per_minute
    }

    dynamic "database_flags" {
      for_each = local.merged_database_flags
      content {
        name  = database_flags.value.name
        value = database_flags.value.value
      }
    }
  }

  deletion_protection = var.deletion_protection
}

resource "google_sql_database" "databases" {
  for_each  = { for db in var.databases : db.name => db }
  name      = each.value.name
  instance  = google_sql_database_instance.default.name
  project   = var.project_id
  charset   = each.value.charset
  collation = each.value.collation
}

resource "google_sql_user" "iam_users" {
  for_each = toset(var.iam_users)
  name     = each.value
  instance = google_sql_database_instance.default.name
  project  = var.project_id
  type     = "CLOUD_IAM_USER"
}

resource "google_sql_user" "iam_service_accounts" {
  for_each = toset(var.iam_service_accounts)
  name     = endswith(each.value, ".gserviceaccount.com") ? trimsuffix(each.value, ".gserviceaccount.com") : each.value
  instance = google_sql_database_instance.default.name
  project  = var.project_id
  type     = "CLOUD_IAM_SERVICE_ACCOUNT"
}

resource "google_sql_user" "db_users" {
  for_each = { for u in var.db_users : u.name => u }
  name     = each.value.name
  instance = google_sql_database_instance.default.name
  project  = var.project_id
  password = each.value.password
  type     = "BUILT_IN"
}
