locals {
  is_prod            = var.environment == "prod"
  network_project_id = coalesce(var.network_project_id, var.project_id)
  private_network    = "projects/${local.network_project_id}/global/networks/apps-${var.environment}"

  availability_type = coalesce(var.availability_type, local.is_prod ? "REGIONAL" : "ZONAL")
  update_track      = coalesce(var.maintenance_window.update_track, local.is_prod ? "stable" : "canary")

  # Enforced everywhere: IAM database auth (identity-based audit) and audit/connection logging.
  enforced_flags = {
    "cloudsql.iam_authentication" = "on"
    "cloudsql.enable_pgaudit"     = "on"
    "pgaudit.log"                 = var.pgaudit_log
    "log_connections"             = "on"
    "log_disconnections"          = "on"
    "log_checkpoints"             = "on"
    "log_lock_waits"              = "on"
  }
  database_flags = merge(var.database_flags, local.enforced_flags)

  labels = merge(var.labels, {
    environment = var.environment
    managed_by  = "opentofu"
  })

  iam_user_types = {
    USER            = "CLOUD_IAM_USER"
    SERVICE_ACCOUNT = "CLOUD_IAM_SERVICE_ACCOUNT"
    GROUP           = "CLOUD_IAM_GROUP"
  }
  iam_member_prefix = {
    USER            = "user"
    SERVICE_ACCOUNT = "serviceAccount"
    GROUP           = "group"
  }

  iam_users = { for u in var.iam_users : u.email => u }

  connect_roles = var.grant_connect_roles ? toset(["roles/cloudsql.client", "roles/cloudsql.instanceUser"]) : toset([])
  connect_bindings = {
    for pair in setproduct(keys(local.iam_users), local.connect_roles) :
    "${pair[0]}|${pair[1]}" => { email = pair[0], role = pair[1] }
  }
}

resource "google_sql_database_instance" "this" {
  project             = var.project_id
  name                = var.name
  region              = var.region
  database_version    = var.database_version
  deletion_protection = var.deletion_protection
  encryption_key_name = var.kms_key_name

  settings {
    tier                        = var.tier
    edition                     = var.edition
    availability_type           = local.availability_type
    disk_type                   = var.disk_type
    disk_size                   = var.disk_size_gb
    disk_autoresize             = true
    disk_autoresize_limit       = var.disk_autoresize_limit_gb
    deletion_protection_enabled = var.deletion_protection
    user_labels                 = local.labels

    # Private IP only, on the environment's VPC; SSL always required.
    ip_configuration {
      ipv4_enabled    = false
      private_network = local.private_network
      ssl_mode        = "ENCRYPTED_ONLY"
    }

    dynamic "location_preference" {
      for_each = var.zone == null ? [] : [var.zone]
      content {
        zone           = location_preference.value
        secondary_zone = var.secondary_zone
      }
    }

    backup_configuration {
      enabled                        = true
      start_time                     = var.backup_start_time
      location                       = var.backup_location
      point_in_time_recovery_enabled = true
      transaction_log_retention_days = var.pitr_log_retention_days

      backup_retention_settings {
        retention_unit   = "COUNT"
        retained_backups = var.backup_retained_count
      }
    }

    maintenance_window {
      day          = var.maintenance_window.day
      hour         = var.maintenance_window.hour
      update_track = local.update_track
    }

    insights_config {
      query_insights_enabled  = var.query_insights_enabled
      query_plans_per_minute  = 5
      query_string_length     = 1024
      record_application_tags = true
      record_client_address   = false
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
    precondition {
      condition     = var.edition != "ENTERPRISE_PLUS" || startswith(var.tier, "db-perf-optimized-")
      error_message = "ENTERPRISE_PLUS requires a db-perf-optimized-N-* tier."
    }
    precondition {
      condition     = var.edition != "ENTERPRISE" || startswith(var.tier, "db-custom-") || startswith(var.tier, "db-f1-") || startswith(var.tier, "db-g1-")
      error_message = "ENTERPRISE requires a db-custom-* (or shared-core db-f1/db-g1) tier."
    }
    precondition {
      condition     = var.secondary_zone == null || var.zone != null
      error_message = "secondary_zone requires zone to be set."
    }
  }
}

resource "google_sql_database" "this" {
  for_each = toset(var.databases)

  project  = var.project_id
  instance = google_sql_database_instance.this.name
  name     = each.value
}

# IAM-only logins: no built-in (password) users are created.
resource "google_sql_user" "iam" {
  for_each = local.iam_users

  project  = var.project_id
  instance = google_sql_database_instance.this.name
  type     = local.iam_user_types[each.value.type]
  # Service accounts log in without the ".gserviceaccount.com" suffix.
  name = each.value.type == "SERVICE_ACCOUNT" ? trimsuffix(each.value.email, ".gserviceaccount.com") : each.value.email
}

# Allow the identities to connect, scoped to this instance only.
resource "google_project_iam_member" "connect" {
  for_each = local.connect_bindings

  project = var.project_id
  role    = each.value.role
  member  = "${local.iam_member_prefix[local.iam_users[each.value.email].type]}:${each.value.email}"

  condition {
    title       = "only-${var.name}"
    description = "Limit to Cloud SQL instance ${var.name}"
    expression  = "resource.type == \"sqladmin.googleapis.com/Instance\" && resource.name == \"projects/${var.project_id}/instances/${var.name}\""
  }
}
