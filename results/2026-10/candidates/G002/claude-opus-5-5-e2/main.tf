locals {
  is_prod = var.environment == "prod"

  network_project = coalesce(var.network_project_id, var.project_id)
  network_id      = "projects/${local.network_project}/global/networks/apps-${var.environment}"

  availability_type = coalesce(var.availability_type, local.is_prod ? "REGIONAL" : "ZONAL")
  retained_backups  = coalesce(var.retained_backups, local.is_prod ? 30 : 7)

  # Baseline logging so every instance records who connected; DBAs can override.
  default_flags = {
    log_connections    = "on"
    log_disconnections = "on"
    log_lock_waits     = "on"
    log_temp_files     = "0"
  }

  enforced_flags = merge(
    { "cloudsql.iam_authentication" = "on" },
    var.enable_pgaudit ? { "cloudsql.enable_pgaudit" = "on" } : {},
  )

  database_flags = merge(local.default_flags, var.database_flags, local.enforced_flags)

  labels = merge(var.labels, {
    environment = var.environment
    managed-by  = "opentofu"
    module      = "cloudsql-postgres"
  })

  # IAM principals => Cloud SQL user name + type + IAM member string.
  principals = merge(
    { for u in var.iam_users : "user:${u}" => {
      db_user = u
      type    = "CLOUD_IAM_USER"
    } },
    { for s in var.iam_service_accounts : "serviceAccount:${s}" => {
      db_user = trimsuffix(s, ".gserviceaccount.com")
      type    = "CLOUD_IAM_SERVICE_ACCOUNT"
    } },
    { for g in var.iam_groups : "group:${g}" => {
      db_user = g
      type    = "CLOUD_IAM_GROUP"
    } },
  )

  connect_roles = ["roles/cloudsql.client", "roles/cloudsql.instanceUser"]

  role_bindings = var.grant_connect_roles ? {
    for pair in setproduct(keys(local.principals), local.connect_roles) :
    "${pair[0]}|${pair[1]}" => { member = pair[0], role = pair[1] }
  } : {}
}

resource "google_sql_database_instance" "this" {
  project             = var.project_id
  region              = var.region
  name                = var.name
  database_version    = var.database_version
  encryption_key_name = var.encryption_key_name
  deletion_protection = var.deletion_protection

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

    dynamic "location_preference" {
      for_each = var.zone != null || var.secondary_zone != null ? [1] : []
      content {
        zone           = var.zone
        secondary_zone = local.availability_type == "REGIONAL" ? var.secondary_zone : null
      }
    }

    # Private IP only, on the environment's VPC via private services access.
    ip_configuration {
      ipv4_enabled                                  = false
      private_network                               = local.network_id
      allocated_ip_range                            = var.allocated_ip_range
      ssl_mode                                      = "ENCRYPTED_ONLY"
      enable_private_path_for_google_cloud_services = false
    }

    backup_configuration {
      enabled                        = true
      point_in_time_recovery_enabled = true
      start_time                     = var.backup_start_time
      location                       = var.backup_location
      transaction_log_retention_days = var.transaction_log_retention_days

      backup_retention_settings {
        retained_backups = local.retained_backups
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

    dynamic "database_flags" {
      for_each = local.database_flags
      content {
        name  = database_flags.key
        value = database_flags.value
      }
    }
  }

  lifecycle {
    ignore_changes = [settings[0].disk_size]
  }
}

resource "google_sql_database" "this" {
  for_each = var.databases

  project  = var.project_id
  instance = google_sql_database_instance.this.name
  name     = each.value
}

resource "google_sql_user" "iam" {
  for_each = local.principals

  project  = var.project_id
  instance = google_sql_database_instance.this.name
  name     = each.value.db_user
  type     = each.value.type
}

# Allow each principal to connect (Auth Proxy / connectors) and log in with
# IAM database authentication, scoped to this instance only.
resource "google_project_iam_member" "connect" {
  for_each = local.role_bindings

  project = var.project_id
  role    = each.value.role
  member  = each.value.member

  condition {
    title       = "cloudsql-${var.name}"
    description = "Limit to Cloud SQL instance ${var.name}"
    expression  = "resource.type == \"sqladmin.googleapis.com/Instance\" && resource.name == \"projects/${var.project_id}/instances/${var.name}\""
  }
}
