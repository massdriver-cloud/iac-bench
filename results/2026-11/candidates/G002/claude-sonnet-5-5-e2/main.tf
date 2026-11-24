locals {
  is_prod_like = var.environment != "dev"

  network_project = coalesce(var.network_project_id, var.project_id)
  network         = "projects/${local.network_project}/global/networks/apps-${var.environment}"

  availability_type = coalesce(var.availability_type, local.is_prod_like ? "REGIONAL" : "ZONAL")
  backups_retained  = coalesce(var.backup_retained_count, local.is_prod_like ? 30 : 7)

  # Standard flags every instance carries. These win over user supplied flags.
  enforced_flags = {
    "cloudsql.iam_authentication" = "on"
    "cloudsql.enable_pgaudit"     = "on"
    "pgaudit.log"                 = var.pgaudit_log
    "log_connections"             = "on"
    "log_disconnections"          = "on"
    "log_checkpoints"             = "on"
    "log_lock_waits"              = "on"
    "log_min_duration_statement"  = tostring(var.log_min_duration_statement_ms)
  }
  flags = merge(var.database_flags, local.enforced_flags)

  # Postgres IAM service-account database users omit the .gserviceaccount.com suffix.
  db_users = merge(
    { for e in var.iam_users : e => { name = e, type = "CLOUD_IAM_USER", member = "user:${e}" } },
    { for e in var.iam_groups : e => { name = e, type = "CLOUD_IAM_GROUP", member = "group:${e}" } },
    { for e in var.iam_service_accounts : e => {
      name   = trimsuffix(e, ".gserviceaccount.com")
      type   = "CLOUD_IAM_SERVICE_ACCOUNT"
      member = "serviceAccount:${e}"
    } },
  )

  access_roles = ["roles/cloudsql.client", "roles/cloudsql.instanceUser"]
  access_bindings = {
    for pair in setproduct(keys(local.db_users), local.access_roles) :
    "${pair[0]}|${pair[1]}" => { who = pair[0], role = pair[1] }
  }
}

resource "google_sql_database_instance" "this" {
  project             = var.project_id
  name                = var.name
  region              = var.region
  database_version    = var.database_version
  deletion_protection = var.deletion_protection

  settings {
    edition                     = var.edition
    tier                        = var.tier
    availability_type           = local.availability_type
    disk_type                   = var.disk_type
    disk_size                   = var.disk_size_gb
    disk_autoresize             = true
    deletion_protection_enabled = var.deletion_protection

    user_labels = merge(var.labels, {
      environment = var.environment
      managed-by  = "opentofu"
    })

    ip_configuration {
      ipv4_enabled    = false
      private_network = local.network
      ssl_mode        = "ENCRYPTED_ONLY"
    }

    backup_configuration {
      enabled                        = true
      start_time                     = var.backup_start_time
      point_in_time_recovery_enabled = true
      transaction_log_retention_days = var.point_in_time_recovery_days

      backup_retention_settings {
        retained_backups = local.backups_retained
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
      query_plans_per_minute  = 5
      query_string_length     = 1024
      record_application_tags = true
      record_client_address   = false
    }

    dynamic "database_flags" {
      for_each = local.flags
      content {
        name  = database_flags.key
        value = database_flags.value
      }
    }

    dynamic "location_preference" {
      for_each = var.zone == null ? [] : [var.zone]
      content {
        zone = location_preference.value
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
  for_each = local.db_users

  project  = var.project_id
  instance = google_sql_database_instance.this.name
  name     = each.value.name
  type     = each.value.type
}

# Allow the identities to connect, scoped to this instance only.
resource "google_project_iam_member" "access" {
  for_each = local.access_bindings

  project = var.project_id
  role    = each.value.role
  member  = local.db_users[each.value.who].member

  condition {
    title      = "only-${var.name}"
    expression = "resource.type == \"sqladmin.googleapis.com/Instance\" && resource.name == \"projects/${var.project_id}/instances/${var.name}\""
  }
}
