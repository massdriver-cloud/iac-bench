locals {
  network_project_id = coalesce(var.network_project_id, var.project_id)
  network_name       = "apps-${var.environment}"
  network_self_link  = "projects/${local.network_project_id}/global/networks/${local.network_name}"

  availability_type = coalesce(var.availability_type, var.environment == "prod" ? "REGIONAL" : "ZONAL")
  update_track      = coalesce(var.maintenance_window.update_track, var.environment == "prod" ? "stable" : "canary")

  # Flags that are the same on every instance: IAM auth (identity-based access
  # for the security team), pgaudit and connection logging (auditability).
  enforced_flags = {
    "cloudsql.iam_authentication" = "on"
    "cloudsql.enable_pgaudit"     = "on"
    "pgaudit.log"                 = "role,ddl"
    "log_connections"             = "on"
    "log_disconnections"          = "on"
    "log_checkpoints"             = "on"
    "log_lock_waits"              = "on"
  }

  # Enforced flags win over DBA-supplied ones.
  database_flags = merge(var.database_flags, local.enforced_flags)

  labels = merge(var.labels, {
    environment = var.environment
    managed-by  = "opentofu"
  })

  instance_resource_name = "projects/${var.project_id}/instances/${var.name}"

  iam_members = toset(concat(
    [for u in var.iam_users : "user:${u}"],
    [for s in var.iam_service_accounts : "serviceAccount:${s}"],
    [for g in var.iam_groups : "group:${g}"],
  ))

  connect_roles = ["roles/cloudsql.client", "roles/cloudsql.instanceUser"]

  connect_bindings = var.grant_connect_roles ? {
    for pair in setproduct(tolist(local.iam_members), local.connect_roles) :
    "${pair[1]}|${pair[0]}" => { member = pair[0], role = pair[1] }
  } : {}
}

resource "google_sql_database_instance" "this" {
  name                = var.name
  project             = var.project_id
  region              = var.region
  database_version    = var.database_version
  encryption_key_name = var.encryption_key_name
  deletion_protection = var.deletion_protection

  settings {
    tier                        = var.tier
    edition                     = var.edition
    availability_type           = local.availability_type
    disk_type                   = "PD_SSD"
    disk_size                   = var.disk_size_gb
    disk_autoresize             = true
    disk_autoresize_limit       = var.disk_autoresize_limit_gb
    deletion_protection_enabled = var.deletion_protection
    user_labels                 = local.labels

    dynamic "location_preference" {
      for_each = var.zone == null ? [] : [var.zone]
      content {
        zone = location_preference.value
      }
    }

    # Private IP only, on the environment's VPC via private services access.
    ip_configuration {
      ipv4_enabled       = false
      private_network    = local.network_self_link
      allocated_ip_range = var.allocated_ip_range
      ssl_mode           = "ENCRYPTED_ONLY"
    }

    backup_configuration {
      enabled                        = true
      start_time                     = var.backup_start_time
      point_in_time_recovery_enabled = true
      transaction_log_retention_days = var.pitr_log_retention_days

      backup_retention_settings {
        retained_backups = var.backup_retained_count
        retention_unit   = "COUNT"
      }
    }

    maintenance_window {
      day          = var.maintenance_window.day
      hour         = var.maintenance_window.hour
      update_track = local.update_track
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
  for_each = toset(var.databases)

  name      = each.value
  project   = var.project_id
  instance  = google_sql_database_instance.this.name
  charset   = "UTF8"
  collation = "en_US.UTF8"
}

# ---------------------------------------------------------------------------
# IAM database authentication users (no passwords managed by this module)
# ---------------------------------------------------------------------------

resource "google_sql_user" "iam_user" {
  for_each = var.iam_users

  project  = var.project_id
  instance = google_sql_database_instance.this.name
  name     = each.value
  type     = "CLOUD_IAM_USER"
}

resource "google_sql_user" "iam_service_account" {
  for_each = var.iam_service_accounts

  project  = var.project_id
  instance = google_sql_database_instance.this.name
  # Cloud SQL expects the SA email without the ".gserviceaccount.com" suffix.
  name = trimsuffix(each.value, ".gserviceaccount.com")
  type = "CLOUD_IAM_SERVICE_ACCOUNT"
}

resource "google_sql_user" "iam_group" {
  for_each = var.iam_groups

  project  = var.project_id
  instance = google_sql_database_instance.this.name
  name     = each.value
  type     = "CLOUD_IAM_GROUP"
}

# Allow the identities to connect (Auth Proxy / connectors) and to log in via
# IAM, scoped to this instance only by an IAM condition.
resource "google_project_iam_member" "connect" {
  for_each = local.connect_bindings

  project = var.project_id
  role    = each.value.role
  member  = each.value.member

  condition {
    title       = "only-${var.name}"
    description = "Restrict ${each.value.role} to Cloud SQL instance ${var.name}"
    expression  = "resource.type == \"sqladmin.googleapis.com/Instance\" && resource.name == \"${local.instance_resource_name}\""
  }
}
