locals {
  # Flag configuration: Ensure cloudsql.iam_authentication = "on" is default unless specified
  default_flags = [
    {
      name  = "cloudsql.iam_authentication"
      value = "on"
    }
  ]

  user_has_iam_flag  = contains([for f in var.database_flags : f.name], "cloudsql.iam_authentication")
  all_database_flags = local.user_has_iam_flag ? var.database_flags : concat(local.default_flags, var.database_flags)

  # Formatted members for IAM roles
  iam_user_members = [
    for u in var.iam_users :
    startswith(u, "user:") || startswith(u, "group:") || startswith(u, "serviceAccount:") ? u : "user:${u}"
  ]

  iam_sa_members = [
    for sa in var.iam_service_accounts :
    startswith(sa, "serviceAccount:") ? sa : (
      endswith(sa, ".gserviceaccount.com") ? "serviceAccount:${sa}" : "serviceAccount:${sa}.gserviceaccount.com"
    )
  ]

  all_iam_members = concat(local.iam_user_members, local.iam_sa_members)
}

# Primary Cloud SQL PostgreSQL Instance
resource "google_sql_database_instance" "default" {
  name                = var.name
  project             = var.project_id
  region              = var.region
  database_version    = var.database_version
  deletion_protection = var.deletion_protection
  root_password       = var.root_password

  settings {
    tier                  = var.tier
    availability_type     = var.availability_type
    disk_type             = var.disk_type
    disk_size             = var.disk_size
    disk_autoresize       = var.disk_autoresize
    disk_autoresize_limit = var.disk_autoresize_limit
    user_labels           = var.labels

    ip_configuration {
      ipv4_enabled                                  = var.enable_public_ip
      private_network                               = var.network_id
      allocated_ip_range                            = var.allocated_ip_range
      enable_private_path_for_google_cloud_services = true
      ssl_mode                                      = var.ssl_mode
    }

    backup_configuration {
      enabled                        = var.backup_configuration.enabled
      start_time                     = var.backup_configuration.start_time
      location                       = var.backup_configuration.location
      point_in_time_recovery_enabled = var.backup_configuration.point_in_time_recovery_enabled
      transaction_log_retention_days = var.backup_configuration.transaction_log_retention_days
      backup_retention_settings {
        retained_backups = var.backup_configuration.retained_backups
        retention_unit   = var.backup_configuration.retention_unit
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
    }

    dynamic "database_flags" {
      for_each = local.all_database_flags
      content {
        name  = database_flags.value.name
        value = database_flags.value.value
      }
    }
  }
}

# Create databases
resource "google_sql_database" "databases" {
  for_each = { for db in var.databases : db.name => db }

  name      = each.value.name
  instance  = google_sql_database_instance.default.name
  charset   = each.value.charset
  collation = each.value.collation
  project   = var.project_id
}

# Create built-in database users
resource "google_sql_user" "built_in_users" {
  for_each = { for user in var.users : user.name => user }

  name     = each.key
  instance = google_sql_database_instance.default.name
  password = each.value.password
  type     = "BUILT_IN"
  project  = var.project_id
}

# Create IAM Users (Google Accounts)
resource "google_sql_user" "iam_users" {
  for_each = toset(var.iam_users)

  name     = each.value
  instance = google_sql_database_instance.default.name
  type     = "CLOUD_IAM_USER"
  project  = var.project_id
}

# Create IAM Service Accounts
resource "google_sql_user" "iam_service_accounts" {
  for_each = toset(var.iam_service_accounts)

  name     = trimsuffix(each.value, ".gserviceaccount.com")
  instance = google_sql_database_instance.default.name
  type     = "CLOUD_IAM_SERVICE_ACCOUNT"
  project  = var.project_id
}

# Grant Cloud SQL Client role to IAM identities
resource "google_project_iam_member" "cloudsql_client" {
  for_each = var.grant_iam_roles ? toset(local.all_iam_members) : toset([])

  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = each.value
}

# Grant Cloud SQL Instance User role to IAM identities
resource "google_project_iam_member" "cloudsql_instance_user" {
  for_each = var.grant_iam_roles ? toset(local.all_iam_members) : toset([])

  project = var.project_id
  role    = "roles/cloudsql.instanceUser"
  member  = each.value
}
