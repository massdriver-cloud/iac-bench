terraform {
  required_version = ">= 1.6.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 6.0, < 8.0"
    }
  }
}

# Use the caller's Google provider project. The VPC and its private services
# access connection are prerequisites, not resources owned by this state.
data "google_compute_network" "apps" {
  name = "apps-${var.environment}"
}

locals {
  standard_flags = {
    "cloudsql.iam_authentication" = "on"
    log_connections               = var.database_version == "POSTGRES_18" ? "all" : "on"
    log_disconnections            = "on"
  }

  # Cloud SQL for PostgreSQL expects the service account login without the
  # .gserviceaccount.com suffix; Google's IAM API expects the full email.
  iam_users = merge(
    { for email in var.iam_user_emails : "user:${email}" => {
      name = email
      type = "CLOUD_IAM_USER"
    } },
    { for email in var.iam_service_account_emails : "serviceAccount:${email}" => {
      name = trimsuffix(email, ".gserviceaccount.com")
      type = "CLOUD_IAM_SERVICE_ACCOUNT"
    } }
  )

  iam_grants = {
    for pair in setproduct(toset(keys(local.iam_users)), toset(["roles/cloudsql.instanceUser", "roles/cloudsql.client"])) :
    "${pair[0]}:${pair[1]}" => { member = pair[0], role = pair[1] }
  }
}

resource "google_sql_database_instance" "postgres" {
  project          = data.google_compute_network.apps.project
  name             = var.instance_name
  region           = var.region
  database_version = var.database_version

  # Guard both OpenTofu workflows and deletion via the Cloud SQL API.
  deletion_protection = true

  settings {
    tier                        = var.tier
    edition                     = var.edition
    availability_type           = var.availability_type != null ? var.availability_type : (var.environment == "prod" ? "REGIONAL" : "ZONAL")
    disk_type                   = "PD_SSD"
    disk_size                   = var.initial_disk_size_gb
    disk_autoresize             = true
    deletion_protection_enabled = true
    user_labels                 = merge(var.labels, { environment = var.environment, managed-by = "opentofu" })

    ip_configuration {
      ipv4_enabled    = false
      private_network = data.google_compute_network.apps.self_link
      ssl_mode        = "ENCRYPTED_ONLY"
    }

    backup_configuration {
      enabled                        = true
      point_in_time_recovery_enabled = true
      transaction_log_retention_days = 7

      backup_retention_settings {
        retained_backups = 14
        retention_unit   = "COUNT"
      }
    }

    dynamic "maintenance_window" {
      for_each = var.maintenance_window == null ? [] : [var.maintenance_window]
      content {
        day          = maintenance_window.value.day
        hour         = maintenance_window.value.hour
        update_track = maintenance_window.value.update_track
      }
    }

    dynamic "database_flags" {
      for_each = merge(var.database_flags, local.standard_flags)
      content {
        name  = database_flags.key
        value = database_flags.value
      }
    }
  }

  lifecycle {
    # Cloud SQL grows disks in place; don't try to shrink them back on apply.
    ignore_changes = [settings[0].disk_size]

    precondition {
      condition     = length(distinct([for user in values(local.iam_users) : user.name])) == length(local.iam_users)
      error_message = "Configured IAM principals must have distinct PostgreSQL login names after service account suffixes are stripped."
    }
  }
}

resource "google_sql_database" "database" {
  for_each = var.databases

  project   = google_sql_database_instance.postgres.project
  instance  = google_sql_database_instance.postgres.name
  name      = each.key
  charset   = each.value.charset
  collation = each.value.collation
}

resource "google_sql_user" "iam" {
  for_each = local.iam_users

  project  = google_sql_database_instance.postgres.project
  instance = google_sql_database_instance.postgres.name
  name     = each.value.name
  type     = each.value.type
}

# Conditional, additive grants let a principal log in and use a connector
# without acquiring those permissions on every instance in the project.
resource "google_project_iam_member" "database_access" {
  for_each = local.iam_grants

  project = google_sql_database_instance.postgres.project
  role    = each.value.role
  member  = each.value.member

  condition {
    title      = "cloud-sql-${google_sql_database_instance.postgres.name}"
    expression = "resource.type == 'sqladmin.googleapis.com/Instance' && resource.name == 'projects/${google_sql_database_instance.postgres.project}/instances/${google_sql_database_instance.postgres.name}'"
  }
}
