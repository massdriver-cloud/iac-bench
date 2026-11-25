data "google_compute_network" "apps" {
  name = "apps-${var.environment}"
}

locals {
  standard_flags = {
    "cloudsql.iam_authentication" = "on"
    log_connections               = "on"
    log_disconnections            = "on"
  }

  iam_members = setunion(
    toset([for email in var.iam_users : "user:${email}"]),
    toset([for email in var.iam_service_accounts : "serviceAccount:${email}"])
  )
}

resource "google_sql_database_instance" "postgres" {
  name                = var.instance_name
  region              = var.region
  database_version    = var.database_version
  deletion_protection = var.deletion_protection

  settings {
    edition                     = var.edition
    tier                        = var.tier
    availability_type           = coalesce(var.availability_type, var.environment == "prod" ? "REGIONAL" : "ZONAL")
    disk_size                   = var.initial_disk_size_gb
    disk_autoresize             = true
    deletion_protection_enabled = var.deletion_protection

    user_labels = merge(var.labels, {
      environment = var.environment
      managed-by  = "opentofu"
    })

    ip_configuration {
      ipv4_enabled    = false
      private_network = data.google_compute_network.apps.self_link
      ssl_mode        = "ENCRYPTED_ONLY"
    }

    backup_configuration {
      enabled                        = true
      point_in_time_recovery_enabled = true
      start_time                     = var.backup_start_time
      transaction_log_retention_days = 7

      backup_retention_settings {
        retained_backups = 14
        retention_unit   = "COUNT"
      }
    }

    dynamic "maintenance_window" {
      for_each = var.maintenance_window[*]
      content {
        day  = maintenance_window.value.day
        hour = maintenance_window.value.hour
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
    # Cloud SQL grows this disk automatically and it cannot be shrunk in place.
    ignore_changes = [settings[0].disk_size]

    precondition {
      condition     = length(setintersection(var.iam_users, toset([for email in var.iam_service_accounts : trimsuffix(email, ".gserviceaccount.com")]))) == 0
      error_message = "Human and service account identities must have distinct PostgreSQL login names."
    }
  }
}

resource "google_sql_database" "application" {
  for_each = var.databases

  name      = each.key
  instance  = google_sql_database_instance.postgres.name
  project   = google_sql_database_instance.postgres.project
  charset   = each.value.charset
  collation = each.value.collation
}

resource "google_sql_user" "human" {
  for_each = var.iam_users

  name     = each.value
  instance = google_sql_database_instance.postgres.name
  project  = google_sql_database_instance.postgres.project
  type     = "CLOUD_IAM_USER"
}

resource "google_sql_user" "workload" {
  for_each = var.iam_service_accounts

  name     = trimsuffix(each.value, ".gserviceaccount.com")
  instance = google_sql_database_instance.postgres.name
  project  = google_sql_database_instance.postgres.project
  type     = "CLOUD_IAM_SERVICE_ACCOUNT"
}

# Cloud SQL uses project IAM, but the condition limits each grant to this instance.
resource "google_project_iam_member" "database_access" {
  for_each = {
    for pair in setproduct(local.iam_members, toset(["roles/cloudsql.instanceUser", "roles/cloudsql.client"])) :
    "${pair[0]}:${pair[1]}" => { member = pair[0], role = pair[1] }
  }

  project = google_sql_database_instance.postgres.project
  role    = each.value.role
  member  = each.value.member

  condition {
    title       = "cloudsql-${var.instance_name}"
    description = "Grant Cloud SQL access only to ${var.instance_name}."
    expression  = "resource.name == 'projects/${google_sql_database_instance.postgres.project}/instances/${google_sql_database_instance.postgres.name}'"
  }
}
