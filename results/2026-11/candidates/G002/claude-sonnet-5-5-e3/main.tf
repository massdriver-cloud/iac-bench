locals {
  network_project = coalesce(var.network_project_id, var.project_id)
  network_id      = "projects/${local.network_project}/global/networks/apps-${var.environment}"

  high_availability = coalesce(var.high_availability, var.environment == "prod")

  # Fixed everywhere: DBAs may add flags but not weaken these.
  mandatory_flags = {
    "cloudsql.iam_authentication" = "on"
    "cloudsql.enable_pgaudit"     = "on"
    "pgaudit.log"                 = "ddl,role"
    "log_connections"             = "on"
    "log_disconnections"          = "on"
    "log_checkpoints"             = "on"
    "log_lock_waits"              = "on"
  }
  database_flags = merge(var.database_flags, local.mandatory_flags)

  iam_users = { for u in var.iam_users : u.email => u }

  iam_member_prefix = {
    USER            = "user"
    SERVICE_ACCOUNT = "serviceAccount"
    GROUP           = "group"
  }

  # Cloud SQL IAM database user names for service accounts omit the domain suffix.
  iam_db_user_name = {
    for email, u in local.iam_users :
    email => u.type == "SERVICE_ACCOUNT" ? trimsuffix(email, ".gserviceaccount.com") : email
  }

  iam_db_user_type = {
    USER            = "CLOUD_IAM_USER"
    SERVICE_ACCOUNT = "CLOUD_IAM_SERVICE_ACCOUNT"
    GROUP           = "CLOUD_IAM_GROUP"
  }

  instance_roles = ["roles/cloudsql.instanceUser", "roles/cloudsql.client"]

  iam_bindings = var.manage_iam_bindings ? {
    for pair in setproduct(keys(local.iam_users), local.instance_roles) :
    "${pair[0]}|${pair[1]}" => { email = pair[0], role = pair[1] }
  } : {}
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
    availability_type           = local.high_availability ? "REGIONAL" : "ZONAL"
    disk_type                   = var.disk_type
    disk_size                   = var.disk_size_gb
    disk_autoresize             = true
    deletion_protection_enabled = var.deletion_protection

    user_labels = merge(var.labels, { environment = var.environment })

    dynamic "location_preference" {
      for_each = var.availability_zone == null ? [] : [var.availability_zone]
      content {
        zone = location_preference.value
      }
    }

    ip_configuration {
      ipv4_enabled       = false
      private_network    = local.network_id
      allocated_ip_range = var.allocated_ip_range
      ssl_mode           = "ENCRYPTED_ONLY"
    }

    backup_configuration {
      enabled                        = true
      start_time                     = var.backup_start_time
      point_in_time_recovery_enabled = true
      transaction_log_retention_days = var.point_in_time_recovery_days

      backup_retention_settings {
        retained_backups = var.retained_backups
        retention_unit   = "COUNT"
      }
    }

    maintenance_window {
      day          = var.maintenance_window_day
      hour         = var.maintenance_window_hour
      update_track = var.maintenance_update_track
    }

    insights_config {
      query_insights_enabled  = true
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
}

resource "google_sql_database" "this" {
  for_each = toset(var.databases)

  project  = var.project_id
  instance = google_sql_database_instance.this.name
  name     = each.value
}

resource "google_sql_user" "iam" {
  for_each = local.iam_users

  project  = var.project_id
  instance = google_sql_database_instance.this.name
  name     = local.iam_db_user_name[each.key]
  type     = local.iam_db_user_type[each.value.type]
}

resource "google_project_iam_member" "instance_access" {
  for_each = local.iam_bindings

  project = var.project_id
  role    = each.value.role
  member  = "${local.iam_member_prefix[local.iam_users[each.value.email].type]}:${each.value.email}"

  condition {
    title       = "only-${var.name}"
    description = "Limit ${each.value.role} to the ${var.name} Cloud SQL instance."
    expression  = "resource.type == \"sqladmin.googleapis.com/Instance\" && resource.name == \"projects/${var.project_id}/instances/${var.name}\""
  }
}
