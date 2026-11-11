locals {
  # Security baseline wins over caller tuning. These flags are also rejected in
  # the input validation, so attempted overrides fail rather than being ignored.
  standard_database_flags = {
    "cloudsql.iam_authentication" = "on"
    "cloudsql.enable_pgaudit"     = "on"
    "pgaudit.log"                 = "all"
    "log_connections"             = "on"
    "log_disconnections"          = "on"
  }
  database_flags = merge(var.database_flags, local.standard_database_flags)
  iam_members = {
    for email, kind in var.iam_principals : email => "${kind == "IAM_SERVICE_ACCOUNT" ? "serviceAccount" : kind == "IAM_GROUP" ? "group" : "user"}:${email}"
  }
  iam_grants = {
    for grant in flatten([
      for email, member in local.iam_members : [
        for role in ["roles/cloudsql.client", "roles/cloudsql.instanceUser"] : {
          key    = "${email}/${role}"
          member = member
          role   = role
        }
      ]
    ]) : grant.key => grant
  }
}

resource "google_project_service" "sqladmin" {
  project            = var.project_id
  service            = "sqladmin.googleapis.com"
  disable_on_destroy = false
}

resource "google_sql_database_instance" "postgres" {
  project             = var.project_id
  name                = var.instance_name
  region              = var.region
  database_version    = var.postgres_version
  deletion_protection = var.deletion_protection

  settings {
    edition                     = "ENTERPRISE"
    tier                        = var.tier
    availability_type           = var.availability_type
    disk_type                   = "PD_SSD"
    disk_size                   = var.disk_size_gb
    disk_autoresize             = true
    deletion_protection_enabled = var.deletion_protection
    connector_enforcement       = "REQUIRED"
    user_labels                 = var.labels

    ip_configuration {
      ipv4_enabled    = false
      private_network = var.network_self_link
      ssl_mode        = "ENCRYPTED_ONLY"
    }

    backup_configuration {
      enabled                        = true
      start_time                     = var.backup_start_time
      point_in_time_recovery_enabled = true
      transaction_log_retention_days = var.pitr_days
      backup_retention_settings {
        retained_backups = var.retained_backups
        retention_unit   = "COUNT"
      }
    }

    maintenance_window {
      day          = var.maintenance_window.day
      hour         = var.maintenance_window.hour
      update_track = var.maintenance_window.update_track
    }

    dynamic "database_flags" {
      for_each = local.database_flags
      content {
        name  = database_flags.key
        value = database_flags.value
      }
    }
  }

  depends_on = [google_project_service.sqladmin]
}

resource "google_sql_database" "database" {
  for_each = var.databases
  project  = var.project_id
  instance = google_sql_database_instance.postgres.name
  name     = each.value
}

resource "google_sql_user" "iam" {
  for_each = var.iam_principals
  project  = var.project_id
  instance = google_sql_database_instance.postgres.name
  # PostgreSQL service account usernames omit the .gserviceaccount.com suffix.
  name = each.value == "IAM_SERVICE_ACCOUNT" ? trimsuffix(each.key, ".gserviceaccount.com") : each.key
  type = each.value
}

resource "google_project_iam_member" "database_access" {
  for_each = local.iam_grants
  project  = var.project_id
  role     = each.value.role
  member   = each.value.member

  condition {
    title       = "cloudsql-${var.instance_name}"
    description = "Connect and authenticate only to this PostgreSQL instance."
    expression  = "resource.name == 'projects/${var.project_id}/instances/${google_sql_database_instance.postgres.name}' && resource.type == 'sqladmin.googleapis.com/Instance'"
  }

  depends_on = [google_project_service.sqladmin]
}
