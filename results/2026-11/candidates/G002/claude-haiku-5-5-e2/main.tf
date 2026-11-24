data "google_compute_network" "apps" {
  name    = local.network_name
  project = local.network_project
}

resource "random_password" "postgres" {
  length  = 40
  special = false
}

resource "google_sql_database_instance" "this" {
  name                = var.instance_name
  project             = var.project_id
  region              = var.region
  database_version    = var.database_version
  deletion_protection = true

  lifecycle {
    precondition {
      condition     = length(local.locked_flag_collisions) == 0
      error_message = "additional_database_flags sets locked baseline flags: ${join(", ", local.locked_flag_collisions)}. These are fixed by the module."
    }

    precondition {
      condition     = !local.is_prod || var.availability_type == "REGIONAL"
      error_message = "Production instances must use availability_type REGIONAL."
    }
  }

  settings {
    edition           = var.edition
    tier              = var.tier
    availability_type = var.availability_type
    user_labels       = local.labels

    disk_type             = var.disk_type
    disk_size             = var.disk_size_gb
    disk_autoresize       = true
    disk_autoresize_limit = var.disk_autoresize_limit_gb

    # Private IP only, attached to the environment's apps network.
    # No public IP and no authorized networks.
    ip_configuration {
      ipv4_enabled                                  = false
      private_network                               = data.google_compute_network.apps.self_link
      enable_private_path_for_google_cloud_services = true
      ssl_mode                                      = "ENCRYPTED_ONLY"
    }

    # Clients must go through the Cloud SQL Auth Proxy or connectors, which
    # authenticate with the caller's Google identity.
    connector_enforcement = "REQUIRED"

    backup_configuration {
      enabled                        = true
      start_time                     = var.backup_start_time
      point_in_time_recovery_enabled = true
      transaction_log_retention_days = 7

      backup_retention_settings {
        retained_backups = var.backup_retained_count
        retention_unit   = "COUNT"
      }
    }

    maintenance_window {
      day          = var.maintenance_day
      hour         = var.maintenance_hour
      update_track = var.maintenance_track
    }

    insights_config {
      query_insights_enabled  = true
      query_string_length     = 1024
      record_application_tags = true
      record_client_address   = true
    }

    password_validation_policy {
      enable_password_policy      = true
      min_length                  = 16
      complexity                  = "COMPLEXITY_DEFAULT"
      reuse_interval              = 5
      disallow_username_substring = true
    }

    dynamic "database_flags" {
      for_each = local.database_flags
      content {
        name  = database_flags.value.name
        value = database_flags.value.value
      }
    }
  }
}

# Break-glass superuser. Cloud SQL always creates the built-in postgres role,
# so the module sets its password from a generated value kept in state.
# Day-to-day access goes through the IAM principals in users.tf.
resource "google_sql_user" "postgres" {
  name     = "postgres"
  project  = var.project_id
  instance = google_sql_database_instance.this.name
  password = random_password.postgres.result
}

resource "google_sql_database" "this" {
  for_each = toset(var.databases)

  name     = each.value
  project  = var.project_id
  instance = google_sql_database_instance.this.name
}
