locals {
  network_project_id = coalesce(var.network_project_id, var.project_id)
  network_name       = "apps-${var.environment}"
  network_id         = "projects/${local.network_project_id}/global/networks/${local.network_name}"

  is_prod = var.environment == "prod"

  availability_type   = coalesce(var.availability_type, local.is_prod ? "REGIONAL" : "ZONAL")
  deletion_protection = local.is_prod ? true : var.deletion_protection

  # Flags that are the same on every instance. DBAs cannot override these.
  enforced_database_flags = {
    "cloudsql.iam_authentication" = "on"
    "log_connections"             = "on"
    "log_disconnections"          = "on"
    "log_checkpoints"             = "on"
    "log_lock_waits"              = "on"
    "log_temp_files"              = "0"
  }

  conflicting_flags = setintersection(keys(var.database_flags), keys(local.enforced_database_flags))
  database_flags    = merge(var.database_flags, local.enforced_database_flags)

  labels = merge(
    var.labels,
    {
      environment = var.environment
      managed-by  = "opentofu"
      engine      = "postgresql"
    },
  )

  # Cloud SQL IAM user naming: service accounts drop the ".gserviceaccount.com" suffix.
  iam_users = {
    for email in var.iam_users : email => {
      is_service_account = endswith(email, ".gserviceaccount.com")
      sql_user_name      = endswith(email, ".gserviceaccount.com") ? trimsuffix(email, ".gserviceaccount.com") : email
      member             = endswith(email, ".gserviceaccount.com") ? "serviceAccount:${email}" : "user:${email}"
    }
  }

  # Roles each identity needs to connect, scoped to this instance via an IAM condition.
  login_roles = toset(["roles/cloudsql.instanceUser", "roles/cloudsql.client"])

  iam_role_members = {
    for pair in setproduct(keys(local.iam_users), local.login_roles) :
    "${pair[0]}|${pair[1]}" => {
      email = pair[0]
      role  = pair[1]
    }
  }
}

resource "google_sql_database_instance" "this" {
  project          = var.project_id
  name             = var.name
  region           = var.region
  database_version = var.database_version

  encryption_key_name = var.kms_key_name
  deletion_protection = local.deletion_protection

  settings {
    tier              = var.tier
    edition           = var.edition
    availability_type = local.availability_type

    disk_type             = var.disk_type
    disk_size             = var.disk_size_gb
    disk_autoresize       = true
    disk_autoresize_limit = var.disk_autoresize_limit_gb

    deletion_protection_enabled = local.deletion_protection
    connector_enforcement       = var.connector_enforcement
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
      point_in_time_recovery_enabled = true
      start_time                     = var.backup_start_time
      location                       = var.backup_location
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
      query_plans_per_minute  = 5
    }

    dynamic "data_cache_config" {
      for_each = var.edition == "ENTERPRISE_PLUS" ? [1] : []
      content {
        data_cache_enabled = var.data_cache_enabled
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
    precondition {
      condition     = length(local.conflicting_flags) == 0
      error_message = "database_flags may not override module-enforced flags: ${join(", ", sort(local.conflicting_flags))}."
    }

    precondition {
      condition     = !local.is_prod || local.availability_type == "REGIONAL"
      error_message = "prod instances must be REGIONAL (high availability)."
    }

    precondition {
      condition     = !local.is_prod || var.deletion_protection
      error_message = "deletion_protection cannot be disabled in prod."
    }
  }

  timeouts {
    create = "60m"
    update = "60m"
    delete = "60m"
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

resource "google_sql_user" "iam" {
  for_each = local.iam_users

  project  = var.project_id
  instance = google_sql_database_instance.this.name
  name     = each.value.sql_user_name
  type     = each.value.is_service_account ? "CLOUD_IAM_SERVICE_ACCOUNT" : "CLOUD_IAM_USER"
}

# Connect/login roles, conditioned on this instance so that listing an identity here
# does not open any other instance in the project.
resource "google_project_iam_member" "login" {
  for_each = local.iam_role_members

  project = var.project_id
  role    = each.value.role
  member  = local.iam_users[each.value.email].member

  condition {
    title       = "cloudsql-${var.name}"
    description = "Access limited to Cloud SQL instance ${var.name}"
    expression  = "resource.type == \"sqladmin.googleapis.com/Instance\" && resource.name == \"projects/${var.project_id}/instances/${var.name}\""
  }
}
