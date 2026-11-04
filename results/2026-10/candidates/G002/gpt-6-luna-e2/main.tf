terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 5.0, < 8.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

locals {
  network_project_id = coalesce(var.network_project_id, var.project_id)
  private_network    = "projects/${local.network_project_id}/global/networks/apps-${var.environment}"

  # IAM database authentication is mandatory for this standard. Callers may
  # supply additional PostgreSQL flags, but cannot disable or override it.
  database_flags = merge(var.database_flags, {
    "cloudsql.iam_authentication" = "on"
  })

  labels = merge(var.labels, {
    environment = var.environment
    managed_by  = "opentofu"
  })
}

resource "google_sql_database_instance" "postgres" {
  project          = var.project_id
  name             = var.instance_name
  region           = var.region
  database_version = var.database_version

  deletion_protection = var.deletion_protection

  settings {
    tier                        = var.tier
    edition                     = "ENTERPRISE"
    availability_type           = "REGIONAL"
    disk_type                   = "PD_SSD"
    disk_size                   = var.initial_disk_size_gb
    disk_autoresize             = true
    disk_autoresize_limit       = var.disk_autoresize_limit_gb
    user_labels                 = local.labels
    deletion_protection_enabled = var.deletion_protection

    backup_configuration {
      enabled                        = true
      point_in_time_recovery_enabled = true
      transaction_log_retention_days = 7

      backup_retention_settings {
        retained_backups = 7
        retention_unit   = "COUNT"
      }
    }

    ip_configuration {
      ipv4_enabled                                  = false
      private_network                               = local.private_network
      ssl_mode                                      = "ENCRYPTED_ONLY"
      enable_private_path_for_google_cloud_services = false
    }

    insights_config {
      query_insights_enabled  = true
      query_string_length     = 1024
      record_application_tags = true
      record_client_address   = true
    }

    maintenance_window {
      day          = var.maintenance_day
      hour         = var.maintenance_hour
      update_track = "stable"
    }

    dynamic "database_flags" {
      for_each = local.database_flags
      content {
        name  = database_flags.key
        value = database_flags.value
      }
    }
  }
}

resource "google_sql_database" "default" {
  project  = var.project_id
  instance = google_sql_database_instance.postgres.name
  name     = var.database_name
}

# These create PostgreSQL IAM-authenticated database principals. Granting
# cloudsql.instances.login/connect IAM permissions remains with the identity /
# security owners; this module deliberately does not grant project-wide IAM.
resource "google_sql_user" "iam" {
  for_each = var.iam_database_users

  project  = var.project_id
  instance = google_sql_database_instance.postgres.name
  name     = each.value.database_username
  type     = each.value.type
}
