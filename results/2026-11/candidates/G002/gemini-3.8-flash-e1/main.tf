data "google_client_config" "current" {}

locals {
  project_id = coalesce(var.project_id, data.google_client_config.current.project)
  region     = coalesce(var.region, data.google_client_config.current.region, "us-central1")

  is_prod = contains(["apps-prod", "prod"], var.environment)

  normalized_environment = contains(["apps-prod", "prod"], var.environment) ? "apps-prod" : (
    contains(["apps-staging", "staging"], var.environment) ? "apps-staging" : "apps-dev"
  )

  environment_network_map = {
    "apps-dev"     = "apps-dev"
    "dev"          = "apps-dev"
    "apps-staging" = "apps-staging"
    "staging"      = "apps-staging"
    "apps-prod"    = "apps-prod"
    "prod"         = "apps-prod"
  }

  target_network = coalesce(
    var.network,
    lookup(local.environment_network_map, var.environment, var.environment)
  )

  is_network_path = can(regex("^projects/", local.target_network))
}

data "google_compute_network" "vpc" {
  count   = local.is_network_path ? 0 : 1
  name    = local.target_network
  project = local.project_id
}

locals {
  network_link = local.is_network_path ? local.target_network : data.google_compute_network.vpc[0].id

  effective_availability_type = coalesce(
    var.availability_type,
    local.is_prod ? "REGIONAL" : "ZONAL"
  )

  effective_deletion_protection = coalesce(
    var.deletion_protection,
    local.is_prod ? true : false
  )

  effective_retained_backups = coalesce(
    var.retained_backups,
    local.is_prod ? 30 : 7
  )

  user_flags_map = { for f in var.database_flags : f.name => f.value }

  effective_database_flags = merge(
    { "cloudsql.iam_authentication" = "on" },
    local.user_flags_map
  )

  default_labels = {
    environment = local.normalized_environment
    managed_by  = "opentofu"
  }
  merged_labels = merge(local.default_labels, var.labels)
}

resource "google_sql_database_instance" "postgres" {
  name                = var.name
  database_version    = var.database_version
  region              = local.region
  project             = local.project_id
  deletion_protection = local.effective_deletion_protection

  settings {
    tier              = var.tier
    edition           = var.edition
    activation_policy = var.activation_policy
    availability_type = local.effective_availability_type

    disk_type             = var.disk_type
    disk_size             = var.disk_size
    disk_autoresize       = var.disk_autoresize
    disk_autoresize_limit = var.disk_autoresize_limit

    user_labels = local.merged_labels

    ip_configuration {
      ipv4_enabled                                  = var.ipv4_enabled
      private_network                               = local.network_link
      allocated_ip_range                            = var.allocated_ip_range
      enable_private_path_for_google_cloud_services = true
      ssl_mode                                      = var.ssl_mode
    }

    backup_configuration {
      enabled                        = var.backup_enabled
      point_in_time_recovery_enabled = var.backup_enabled ? var.point_in_time_recovery_enabled : false
      start_time                     = var.backup_start_time
      transaction_log_retention_days = var.transaction_log_retention_days

      backup_retention_settings {
        retained_backups = local.effective_retained_backups
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
      for_each = local.effective_database_flags
      content {
        name  = database_flags.key
        value = database_flags.value
      }
    }

    dynamic "location_preference" {
      for_each = var.zone != null ? [var.zone] : []
      content {
        zone = location_preference.value
      }
    }
  }
}

resource "google_sql_database" "databases" {
  for_each = { for db in var.databases : db.name => db }

  name      = each.value.name
  instance  = google_sql_database_instance.postgres.name
  project   = local.project_id
  charset   = each.value.charset
  collation = each.value.collation
}

resource "google_sql_user" "iam_users" {
  for_each = toset(var.iam_users)

  name     = each.value
  instance = google_sql_database_instance.postgres.name
  project  = local.project_id
  type     = "CLOUD_IAM_USER"
}

resource "google_sql_user" "iam_service_accounts" {
  for_each = toset([for sa in var.iam_service_accounts : trimsuffix(sa, ".gserviceaccount.com")])

  name     = each.value
  instance = google_sql_database_instance.postgres.name
  project  = local.project_id
  type     = "CLOUD_IAM_SERVICE_ACCOUNT"
}

resource "google_sql_user" "custom_users" {
  for_each = {
    for u in var.users : u.name => u
    if !contains(var.iam_users, u.name) &&
    !contains([for sa in var.iam_service_accounts : trimsuffix(sa, ".gserviceaccount.com")], trimsuffix(u.name, ".gserviceaccount.com"))
  }

  name     = each.value.type == "CLOUD_IAM_SERVICE_ACCOUNT" ? trimsuffix(each.value.name, ".gserviceaccount.com") : each.value.name
  instance = google_sql_database_instance.postgres.name
  project  = local.project_id
  password = each.value.password
  type     = each.value.type
}
