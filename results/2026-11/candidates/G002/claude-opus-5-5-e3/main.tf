locals {
  network_project = coalesce(var.network_project_id, var.project_id)
  network_id      = "projects/${local.network_project}/global/networks/apps-${var.environment}"

  availability_type = coalesce(var.availability_type, var.environment == "prod" ? "REGIONAL" : "ZONAL")

  # Settings that must be identical on every instance. These win over
  # anything supplied in var.database_flags.
  enforced_flags = {
    "cloudsql.iam_authentication" = "on"
    "cloudsql.enable_pgaudit"     = "on"
    "pgaudit.log"                 = var.pgaudit_log_classes
    "log_connections"             = "on"
    "log_disconnections"          = "on"
  }

  database_flags = merge(var.database_flags, local.enforced_flags)

  labels = merge(var.labels, {
    environment = var.environment
    managed-by  = "opentofu"
    instance    = var.name
  })

  # Cloud SQL strips the domain from service account user names.
  sa_user_names = { for sa in var.iam_service_accounts : sa => trimsuffix(sa, ".gserviceaccount.com") }

  iam_members = concat(
    [for u in var.iam_users : "user:${u}"],
    [for s in var.iam_service_accounts : "serviceAccount:${s}"],
    [for g in var.iam_groups : "group:${g}"],
  )

  project_bindings = var.grant_project_iam ? merge(
    { for m in local.iam_members : "instanceUser|${m}" => { role = "roles/cloudsql.instanceUser", member = m } },
    { for m in local.iam_members : "client|${m}" => { role = "roles/cloudsql.client", member = m } },
  ) : {}
}

resource "google_sql_database_instance" "this" {
  name                = var.name
  project             = var.project_id
  region              = var.region
  database_version    = var.database_version
  encryption_key_name = var.encryption_key_name
  deletion_protection = true

  settings {
    tier                        = var.tier
    edition                     = var.edition
    availability_type           = local.availability_type
    disk_type                   = var.disk_type
    disk_size                   = var.disk_size_gb
    disk_autoresize             = true
    disk_autoresize_limit       = var.disk_autoresize_limit_gb
    deletion_protection_enabled = true
    user_labels                 = local.labels

    ip_configuration {
      ipv4_enabled                                  = false
      private_network                               = local.network_id
      allocated_ip_range                            = var.allocated_ip_range
      ssl_mode                                      = "ENCRYPTED_ONLY"
      enable_private_path_for_google_cloud_services = true
    }

    backup_configuration {
      enabled                        = true
      start_time                     = var.backup_start_time
      location                       = var.backup_location
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

    insights_config {
      query_insights_enabled  = true
      query_string_length     = 1024
      record_application_tags = true
      record_client_address   = true
    }

    dynamic "location_preference" {
      for_each = var.zone != null || var.secondary_zone != null ? [1] : []
      content {
        zone           = var.zone
        secondary_zone = local.availability_type == "REGIONAL" ? var.secondary_zone : null
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
    # Storage auto-resize grows the disk; don't fight it.
    ignore_changes = [settings[0].disk_size]

    precondition {
      condition     = var.edition == "ENTERPRISE_PLUS" || var.transaction_log_retention_days <= 7
      error_message = "transaction_log_retention_days above 7 requires the ENTERPRISE_PLUS edition."
    }

    precondition {
      condition     = var.edition != "ENTERPRISE_PLUS" || startswith(var.tier, "db-perf-optimized-")
      error_message = "ENTERPRISE_PLUS requires a db-perf-optimized-N-* tier."
    }
  }
}

resource "google_sql_database" "this" {
  for_each = var.databases

  project   = var.project_id
  instance  = google_sql_database_instance.this.name
  name      = each.key
  charset   = each.value.charset
  collation = each.value.collation
}

resource "google_sql_user" "iam_user" {
  for_each = var.iam_users

  project  = var.project_id
  instance = google_sql_database_instance.this.name
  name     = each.value
  type     = "CLOUD_IAM_USER"
}

resource "google_sql_user" "iam_service_account" {
  for_each = local.sa_user_names

  project  = var.project_id
  instance = google_sql_database_instance.this.name
  name     = each.value
  type     = "CLOUD_IAM_SERVICE_ACCOUNT"
}

resource "google_sql_user" "iam_group" {
  for_each = var.iam_groups

  project  = var.project_id
  instance = google_sql_database_instance.this.name
  name     = each.value
  type     = "CLOUD_IAM_GROUP"
}

resource "google_project_iam_member" "access" {
  for_each = local.project_bindings

  project = var.project_id
  role    = each.value.role
  member  = each.value.member
}
