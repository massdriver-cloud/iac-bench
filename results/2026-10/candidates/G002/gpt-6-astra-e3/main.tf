locals {
  iam_types = {
    USER            = "CLOUD_IAM_USER"
    SERVICE_ACCOUNT = "CLOUD_IAM_SERVICE_ACCOUNT"
    GROUP           = "CLOUD_IAM_GROUP"
  }
  member_prefixes = {
    USER            = "user"
    SERVICE_ACCOUNT = "serviceAccount"
    GROUP           = "group"
  }
  iam_grants = { for grant in flatten([
    for email, kind in var.iam_principals : [
      for role in ["roles/cloudsql.client", "roles/cloudsql.instanceUser"] : {
        key    = "${email}/${role}"
        member = "${local.member_prefixes[kind]}:${email}"
        role   = role
      }
    ]
  ]) : grant.key => grant }
}

resource "google_sql_database_instance" "postgres" {
  project             = var.project_id
  name                = var.instance_name
  region              = var.region
  database_version    = var.database_version
  deletion_protection = var.deletion_protection

  settings {
    tier                        = var.tier
    edition                     = var.edition
    availability_type           = var.availability_type
    activation_policy           = "ALWAYS"
    disk_type                   = "PD_SSD"
    disk_size                   = var.disk_size_gb
    disk_autoresize             = true
    disk_autoresize_limit       = var.disk_autoresize_limit_gb
    deletion_protection_enabled = var.deletion_protection
    connector_enforcement       = "REQUIRED"
    user_labels                 = var.labels

    ip_configuration {
      ipv4_enabled    = false
      private_network = var.private_network
      ssl_mode        = "ENCRYPTED_ONLY"
    }

    backup_configuration {
      enabled                        = true
      start_time                     = var.backup_start_time
      point_in_time_recovery_enabled = true
      transaction_log_retention_days = var.transaction_log_retention_days
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
      for_each = merge(var.database_flags, { "cloudsql.iam_authentication" = "on" })
      content {
        name  = database_flags.key
        value = database_flags.value
      }
    }
  }

  lifecycle {
    precondition {
      condition     = var.disk_autoresize_limit_gb == 0 || var.disk_autoresize_limit_gb >= var.disk_size_gb
      error_message = "Auto-growth limit must be zero (unlimited) or at least the initial disk size."
    }
  }
}

resource "google_sql_database" "application" {
  for_each = var.databases

  project         = var.project_id
  instance        = google_sql_database_instance.postgres.name
  name            = each.value
  charset         = "UTF8"
  deletion_policy = var.deletion_protection ? "ABANDON" : "DELETE"
}

resource "google_sql_user" "iam" {
  for_each = var.iam_principals

  project  = var.project_id
  instance = google_sql_database_instance.postgres.name
  name     = each.value == "SERVICE_ACCOUNT" ? trimsuffix(each.key, ".gserviceaccount.com") : each.key
  type     = local.iam_types[each.value]
}

# Additive grants, not authoritative policies. Conditions prevent this module's
# grants from allowing connection/login to other instances in the project.
resource "google_project_iam_member" "database_access" {
  for_each = local.iam_grants

  project = var.project_id
  member  = each.value.member
  role    = each.value.role

  condition {
    title       = "cloudsql-${var.instance_name}"
    description = "Connection and IAM database login to ${var.instance_name} only"
    expression  = "resource.name == 'projects/${var.project_id}/instances/${google_sql_database_instance.postgres.name}' && resource.service == 'sqladmin.googleapis.com'"
  }
}
