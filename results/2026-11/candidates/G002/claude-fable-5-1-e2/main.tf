locals {
  is_prod = var.environment == "prod"

  instance_name = var.use_random_suffix ? "${var.name}-${random_id.suffix[0].hex}" : var.name

  network_project_id = coalesce(var.network_project_id, var.project_id)
  network_self_link = coalesce(
    var.network_self_link,
    "projects/${local.network_project_id}/global/networks/apps-${var.environment}",
  )

  availability_type = coalesce(var.availability_type, local.is_prod ? "REGIONAL" : "ZONAL")
  retained_backups  = coalesce(var.retained_backups, local.is_prod ? 30 : 7)

  # Flags every instance gets, regardless of what the DBA passes in.
  # IAM authentication is the access model the security team audits against;
  # connection logging is what makes that audit possible.
  managed_database_flags = {
    "cloudsql.iam_authentication" = "on"
    "log_connections"             = "on"
    "log_disconnections"          = "on"
  }
  database_flags = merge(var.database_flags, local.managed_database_flags)

  labels = merge(
    {
      environment = var.environment
      engine      = "postgresql"
      managed_by  = "opentofu"
    },
    var.labels,
  )

  # Classify IAM principals from their address.
  iam_users = {
    for email in var.iam_users : email => {
      is_service_account = endswith(email, ".gserviceaccount.com")
      sql_type           = endswith(email, ".gserviceaccount.com") ? "CLOUD_IAM_SERVICE_ACCOUNT" : "CLOUD_IAM_USER"
      # Cloud SQL expects service accounts without the .gserviceaccount.com suffix.
      sql_name   = endswith(email, ".gserviceaccount.com") ? trimsuffix(email, ".gserviceaccount.com") : email
      iam_member = endswith(email, ".gserviceaccount.com") ? "serviceAccount:${email}" : "user:${email}"
    }
  }
  iam_groups = {
    for email in var.iam_groups : email => {
      sql_type   = "CLOUD_IAM_GROUP"
      sql_name   = email
      iam_member = "group:${email}"
    }
  }

  iam_login_members = var.grant_iam_login_roles ? toset(concat(
    [for u in local.iam_users : u.iam_member],
    [for g in local.iam_groups : g.iam_member],
  )) : toset([])

  iam_login_roles = toset(["roles/cloudsql.instanceUser", "roles/cloudsql.client"])

  iam_login_bindings = {
    for pair in setproduct(local.iam_login_members, local.iam_login_roles) :
    "${pair[1]}|${pair[0]}" => { member = pair[0], role = pair[1] }
  }
}

resource "random_id" "suffix" {
  count       = var.use_random_suffix ? 1 : 0
  byte_length = 2
}

###############################################################################
# Instance
###############################################################################

resource "google_sql_database_instance" "this" {
  project             = var.project_id
  name                = local.instance_name
  region              = var.region
  database_version    = var.database_version
  encryption_key_name = var.encryption_key_name
  deletion_protection = var.deletion_protection

  settings {
    edition                     = var.edition
    tier                        = var.tier
    availability_type           = local.availability_type
    activation_policy           = "ALWAYS"
    deletion_protection_enabled = var.deletion_protection

    disk_type             = var.disk_type
    disk_size             = var.disk_size_gb
    disk_autoresize       = true
    disk_autoresize_limit = var.disk_autoresize_limit_gb

    connector_enforcement = var.connector_enforcement
    user_labels           = local.labels

    dynamic "location_preference" {
      for_each = var.zone != null || var.secondary_zone != null ? [1] : []
      content {
        zone           = var.zone
        secondary_zone = local.availability_type == "REGIONAL" ? var.secondary_zone : null
      }
    }

    # Private IP only, on the environment's VPC via the existing private
    # services access peering. No public IP, no authorized networks, TLS required.
    ip_configuration {
      ipv4_enabled                                  = false
      private_network                               = local.network_self_link
      allocated_ip_range                            = var.allocated_ip_range
      enable_private_path_for_google_cloud_services = true
      ssl_mode                                      = var.ssl_mode
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
      day          = var.maintenance_window_day
      hour         = var.maintenance_window_hour
      update_track = "stable"
    }

    dynamic "deny_maintenance_period" {
      for_each = var.deny_maintenance_periods
      content {
        start_date = deny_maintenance_period.value.start_date
        end_date   = deny_maintenance_period.value.end_date
        time       = deny_maintenance_period.value.time
      }
    }

    dynamic "database_flags" {
      for_each = local.database_flags
      content {
        name  = database_flags.key
        value = database_flags.value
      }
    }

    insights_config {
      query_insights_enabled  = true
      query_string_length     = 1024
      record_application_tags = true
      record_client_address   = true
    }

    dynamic "data_cache_config" {
      for_each = var.edition == "ENTERPRISE_PLUS" ? [1] : []
      content {
        data_cache_enabled = var.data_cache_enabled
      }
    }
  }

  lifecycle {
    # The disk auto-resizes; don't fight Cloud SQL over its current size.
    ignore_changes = [settings[0].disk_size]

    precondition {
      condition     = var.edition == "ENTERPRISE_PLUS" || !var.data_cache_enabled
      error_message = "data_cache_enabled requires edition = ENTERPRISE_PLUS."
    }
    precondition {
      condition     = local.availability_type == "REGIONAL" || var.secondary_zone == null
      error_message = "secondary_zone only applies to REGIONAL instances."
    }
    precondition {
      condition     = !local.is_prod || var.deletion_protection
      error_message = "deletion_protection cannot be disabled on prod instances without changing the module."
    }
  }
}

###############################################################################
# Databases
###############################################################################

resource "google_sql_database" "this" {
  for_each = var.databases

  project         = var.project_id
  instance        = google_sql_database_instance.this.name
  name            = each.key
  charset         = each.value.charset
  collation       = each.value.collation
  deletion_policy = var.database_deletion_policy
}

###############################################################################
# IAM database users (no passwords - identities are Google identities)
###############################################################################

resource "google_sql_user" "iam_users" {
  for_each = local.iam_users

  project  = var.project_id
  instance = google_sql_database_instance.this.name
  name     = each.value.sql_name
  type     = each.value.sql_type
}

resource "google_sql_user" "iam_groups" {
  for_each = local.iam_groups

  project  = var.project_id
  instance = google_sql_database_instance.this.name
  name     = each.value.sql_name
  type     = each.value.sql_type
}

# IAM login requires roles/cloudsql.instanceUser; roles/cloudsql.client is needed
# for the Auth Proxy / connectors that GKE and Compute Engine workloads use.
resource "google_project_iam_member" "iam_login" {
  for_each = local.iam_login_bindings

  project = var.project_id
  role    = each.value.role
  member  = each.value.member
}

###############################################################################
# Optional break-glass admin (password auth, secret in Secret Manager)
###############################################################################

resource "random_password" "break_glass_admin" {
  count = var.break_glass_admin != null ? 1 : 0

  length           = 32
  special          = true
  override_special = "!#%^*()-_=+[]{}<>:?"
}

resource "google_sql_user" "break_glass_admin" {
  count = var.break_glass_admin != null ? 1 : 0

  project         = var.project_id
  instance        = google_sql_database_instance.this.name
  name            = var.break_glass_admin
  type            = "BUILT_IN"
  password        = random_password.break_glass_admin[0].result
  deletion_policy = "ABANDON"
}

resource "google_secret_manager_secret" "break_glass_admin" {
  count = var.break_glass_admin != null ? 1 : 0

  project   = var.project_id
  secret_id = "${local.instance_name}-${var.break_glass_admin}-password"
  labels    = local.labels

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "break_glass_admin" {
  count = var.break_glass_admin != null ? 1 : 0

  secret      = google_secret_manager_secret.break_glass_admin[0].id
  secret_data = random_password.break_glass_admin[0].result
}
