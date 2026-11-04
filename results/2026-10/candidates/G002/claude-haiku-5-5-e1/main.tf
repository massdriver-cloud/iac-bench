# The application VPC is owned by the network team. Private services access
# (the servicenetworking connection) must already exist on it; this module
# does not create it.
data "google_compute_network" "apps" {
  name    = local.network_name
  project = coalesce(var.network_project_id, var.project_id)
}

resource "google_sql_database_instance" "this" {
  name                = var.instance_name
  project             = var.project_id
  region              = var.region
  database_version    = var.database_version
  deletion_protection = var.deletion_protection
  encryption_key_name = var.encryption_key_name

  settings {
    edition           = var.edition
    tier              = var.tier
    availability_type = var.availability_type
    activation_policy = "ALWAYS"
    user_labels       = local.common_labels

    disk_type             = "PD_SSD"
    disk_size             = var.disk_size_gb
    disk_autoresize       = true
    disk_autoresize_limit = var.disk_autoresize_limit_gb

    location_preference {
      zone = var.zone
    }

    # Private IP only. Reachable from the apps-<environment> VPC, never from the internet.
    ip_configuration {
      ipv4_enabled       = false
      private_network    = data.google_compute_network.apps.id
      allocated_ip_range = var.allocated_ip_range_name
      ssl_mode           = "ENCRYPTED_ONLY"
    }

    backup_configuration {
      enabled                        = true
      start_time                     = var.backup_start_time
      location                       = var.region
      point_in_time_recovery_enabled = true
      transaction_log_retention_days = var.transaction_log_retention_days

      backup_retention_settings {
        retained_backups = var.retained_backups
        retention_unit   = "COUNT"
      }
    }

    maintenance_window {
      day          = var.maintenance_day
      hour         = var.maintenance_hour
      update_track = var.maintenance_update_track
    }

    insights_config {
      query_insights_enabled  = true
      query_string_length     = 1024
      record_application_tags = true
      record_client_address   = false
    }

    # Built-in database users, if anyone creates them, must meet this policy.
    # Day-to-day access is by IAM identity; see the google_sql_user resources.
    password_validation_policy {
      enable_password_policy      = true
      min_length                  = 16
      complexity                  = "COMPLEXITY_DEFAULT"
      disallow_username_substring = true
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

resource "google_sql_database" "this" {
  for_each = toset(var.databases)

  name     = each.value
  instance = google_sql_database_instance.this.name
  project  = var.project_id
}

# Engineers authenticate with their own Google identity, so the security
# team's audit trail names the person, not a shared password.
resource "google_sql_user" "iam_user" {
  for_each = toset(var.iam_users)

  name     = each.value
  instance = google_sql_database_instance.this.name
  project  = var.project_id
  type     = "CLOUD_IAM_USER"
}

# Workloads on GKE / Compute Engine authenticate as their service account.
# Cloud SQL names these users without the .gserviceaccount.com suffix.
resource "google_sql_user" "iam_service_account" {
  for_each = local.iam_service_account_users

  name     = each.key
  instance = google_sql_database_instance.this.name
  project  = var.project_id
  type     = "CLOUD_IAM_SERVICE_ACCOUNT"
}
