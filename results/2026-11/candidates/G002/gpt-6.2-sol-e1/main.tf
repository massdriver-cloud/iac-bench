data "google_compute_network" "apps" {
  name = "apps-${var.environment}"
}

locals {
  database_flags = merge(var.database_flags, {
    "cloudsql.iam_authentication" = "on"
    log_connections               = "on"
    log_disconnections            = "on"
  })

  iam_member_prefixes = {
    CLOUD_IAM_USER            = "user"
    CLOUD_IAM_SERVICE_ACCOUNT = "serviceAccount"
    CLOUD_IAM_GROUP           = "group"
  }

  iam_members = {
    for email, kind in var.iam_database_users : email => "${local.iam_member_prefixes[kind]}:${email}"
  }

  iam_bindings = {
    for pair in setproduct(toset(keys(local.iam_members)), toset(["roles/cloudsql.client", "roles/cloudsql.instanceUser"])) :
    "${pair[0]}/${pair[1]}" => { member = local.iam_members[pair[0]], role = pair[1] }
  }
}

resource "google_sql_database_instance" "postgres" {
  project             = data.google_compute_network.apps.project
  name                = var.instance_name
  region              = var.region
  database_version    = var.database_version
  deletion_protection = true

  settings {
    edition                     = var.edition
    tier                        = var.tier
    availability_type           = coalesce(var.availability_type, var.environment == "prod" ? "REGIONAL" : "ZONAL")
    disk_type                   = "PD_SSD"
    disk_size                   = var.initial_disk_size_gb
    disk_autoresize             = true
    deletion_protection_enabled = true
    connector_enforcement       = "REQUIRED"
    user_labels                 = merge(var.labels, { environment = var.environment })

    ip_configuration {
      ipv4_enabled    = false
      private_network = data.google_compute_network.apps.self_link
      ssl_mode        = "ENCRYPTED_ONLY"
    }

    backup_configuration {
      enabled                        = true
      point_in_time_recovery_enabled = true
      start_time                     = var.backup.start_time
      transaction_log_retention_days = var.backup.transaction_log_retention_days

      backup_retention_settings {
        retained_backups = var.backup.retained_backups
        retention_unit   = "COUNT"
      }
    }

    dynamic "maintenance_window" {
      for_each = var.maintenance_window[*]
      content {
        day          = maintenance_window.value.day
        hour         = maintenance_window.value.hour
        update_track = maintenance_window.value.update_track
      }
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
    # Do not shrink an automatically grown disk or plan instance replacement.
    ignore_changes = [settings[0].disk_size]

    precondition {
      condition     = var.edition == "ENTERPRISE_PLUS" || var.backup.transaction_log_retention_days <= 7
      error_message = "Enterprise instances support at most 7 days of PITR log retention."
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

  lifecycle {
    prevent_destroy = true
  }
}

resource "google_sql_user" "iam" {
  for_each = var.iam_database_users

  project  = google_sql_database_instance.postgres.project
  instance = google_sql_database_instance.postgres.name
  name     = each.value == "CLOUD_IAM_SERVICE_ACCOUNT" ? trimsuffix(each.key, ".gserviceaccount.com") : each.key
  type     = each.value
}

resource "google_project_iam_member" "sql_access" {
  for_each = local.iam_bindings

  project = google_sql_database_instance.postgres.project
  role    = each.value.role
  member  = each.value.member

  condition {
    title       = "cloud-sql-${google_sql_database_instance.postgres.name}"
    description = "Restrict this grant to the managed Cloud SQL instance."
    expression  = "resource.service == 'sqladmin.googleapis.com' && resource.name == 'projects/${google_sql_database_instance.postgres.project}/instances/${google_sql_database_instance.postgres.name}'"
  }
}
