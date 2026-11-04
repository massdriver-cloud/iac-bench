locals {
  # IAM authentication is not a caller-overridable tuning flag.
  database_flags = merge(var.database_flags, { "cloudsql.iam_authentication" = "on" })
  iam_members = {
    for email, kind in var.iam_users : email => "${kind == "SERVICE_ACCOUNT" ? "serviceAccount" : "user"}:${email}"
  }
}

resource "google_sql_database_instance" "this" {
  project             = var.project_id
  name                = var.name
  region              = var.region
  database_version    = var.postgres_version
  deletion_protection = var.deletion_protection

  settings {
    edition                     = "ENTERPRISE"
    tier                        = var.tier
    availability_type           = var.availability_type
    activation_policy           = "ALWAYS"
    disk_type                   = "PD_SSD"
    disk_size                   = var.disk_size_gb
    disk_autoresize             = true
    disk_autoresize_limit       = 0
    deletion_protection_enabled = var.deletion_protection
    connector_enforcement       = "REQUIRED"
    user_labels                 = merge(var.labels, { managed_by = "opentofu" })

    ip_configuration {
      ipv4_enabled                                  = false
      private_network                               = var.private_network
      enable_private_path_for_google_cloud_services = false
      ssl_mode                                      = "ENCRYPTED_ONLY"
    }

    backup_configuration {
      enabled                        = true
      start_time                     = var.backup_start_time
      location                       = var.region
      point_in_time_recovery_enabled = true
      transaction_log_retention_days = 7
      backup_retention_settings {
        retained_backups = 14
        retention_unit   = "COUNT"
      }
    }

    maintenance_window {
      day          = var.maintenance_window.day
      hour         = var.maintenance_window.hour
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

  lifecycle {
    # Cloud SQL grows disks automatically; do not subsequently attempt to shrink them.
    ignore_changes = [settings[0].disk_size]
  }
}

resource "google_sql_database" "this" {
  for_each = var.databases

  project         = var.project_id
  instance        = google_sql_database_instance.this.name
  name            = each.key
  charset         = each.value.charset
  collation       = each.value.collation
  deletion_policy = "ABANDON"
}

resource "google_project_iam_member" "client" {
  for_each = local.iam_members

  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = each.value

  condition {
    title       = "cloudsql-client-${var.name}"
    description = "Connect only to the managed PostgreSQL instance."
    expression  = "resource.name == 'projects/${var.project_id}/instances/${google_sql_database_instance.this.name}'"
  }
}

resource "google_project_iam_member" "login" {
  for_each = local.iam_members

  project = var.project_id
  role    = "roles/cloudsql.instanceUser"
  member  = each.value

  condition {
    title       = "cloudsql-login-${var.name}"
    description = "IAM database login only to the managed PostgreSQL instance."
    expression  = "resource.name == 'projects/${var.project_id}/instances/${google_sql_database_instance.this.name}'"
  }
}

resource "google_sql_user" "iam" {
  for_each = var.iam_users

  project  = var.project_id
  instance = google_sql_database_instance.this.name
  name     = each.value == "SERVICE_ACCOUNT" ? trimsuffix(each.key, ".gserviceaccount.com") : each.key
  type     = each.value == "SERVICE_ACCOUNT" ? "CLOUD_IAM_SERVICE_ACCOUNT" : "CLOUD_IAM_USER"

  depends_on = [google_project_iam_member.client, google_project_iam_member.login]
}
