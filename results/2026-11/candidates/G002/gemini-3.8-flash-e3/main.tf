provider "google" {}

data "google_project" "current" {
  count = var.project == null ? 1 : 0
}

locals {
  project_id = var.project != null ? var.project : data.google_project.current[0].project_id

  # Support both simple network names (apps-dev, apps-staging, apps-prod) and full network URIs
  is_network_uri = can(regex("^projects/|^https://", var.network))
  network_link   = local.is_network_uri ? var.network : "projects/${local.project_id}/global/networks/${var.network}"

  # Opinionated standard PostgreSQL flags: audit logging, connection tracking, lock monitoring
  standard_flags = {
    "cloudsql.iam_authentication" = "on"
    "cloudsql.enable_pgaudit"     = "on"
    "pgaudit.log"                 = var.pgaudit_log
    "log_connections"             = "on"
    "log_disconnections"          = "on"
    "log_checkpoints"             = "on"
    "log_lock_waits"              = "on"
    "log_temp_files"              = "0"
    "log_min_messages"            = "warning"
  }

  # DBA custom flags merge over standard defaults, but IAM authentication is strictly enforced
  effective_flags = merge(
    local.standard_flags,
    var.database_flags,
    { "cloudsql.iam_authentication" = "on" }
  )

  # Prepare list of IAM identities for optional project-level IAM role assignment
  all_iam_members = concat(
    [for u in var.iam_users : "user:${u}"],
    [for sa in var.iam_service_accounts : "serviceAccount:${sa}"]
  )

  iam_role_pairs = var.grant_iam_roles ? flatten([
    for member in local.all_iam_members : [
      for role in ["roles/cloudsql.instanceUser", "roles/cloudsql.client"] : {
        member = member
        role   = role
      }
    ]
  ]) : []
}

###############################################################################
# Cloud SQL PostgreSQL Primary Database Instance
###############################################################################

resource "google_sql_database_instance" "instance" {
  name             = var.name
  database_version = var.database_version
  region           = var.region
  project          = local.project_id

  settings {
    tier              = var.tier
    edition           = var.edition
    availability_type = var.availability_type
    disk_size         = var.disk_size
    disk_type         = var.disk_type
    disk_autoresize   = var.disk_autoresize
    user_labels       = var.labels

    dynamic "ip_configuration" {
      for_each = [1]
      content {
        # Strictly private IP only - no public IP address allocated
        ipv4_enabled                                  = false
        private_network                               = local.network_link
        allocated_ip_range                            = var.allocated_ip_range
        enable_private_path_for_google_cloud_services = var.enable_private_path_for_google_cloud_services
        ssl_mode                                      = "ENCRYPTED_ONLY"
      }
    }

    backup_configuration {
      enabled                        = true
      point_in_time_recovery_enabled = true
      start_time                     = var.backup_start_time
      transaction_log_retention_days = var.transaction_log_retention_days

      backup_retention_settings {
        retained_backups = var.backup_retention_count
        retention_unit   = "COUNT"
      }
    }

    maintenance_window {
      day          = var.maintenance_window_day
      hour         = var.maintenance_window_hour
      update_track = var.maintenance_window_track
    }

    dynamic "location_preference" {
      for_each = var.zone != null || var.secondary_zone != null ? [1] : []
      content {
        zone           = var.zone
        secondary_zone = var.secondary_zone
      }
    }

    dynamic "insights_config" {
      for_each = var.query_insights_enabled ? [1] : []
      content {
        query_insights_enabled  = true
        query_string_length     = var.query_string_length
        record_application_tags = var.record_application_tags
        record_client_address   = var.record_client_address
        query_plans_per_minute  = var.query_plans_per_minute
      }
    }

    dynamic "database_flags" {
      for_each = local.effective_flags
      content {
        name  = database_flags.key
        value = database_flags.value
      }
    }
  }

  deletion_protection = var.deletion_protection
}

###############################################################################
# Read Replicas (Optional)
###############################################################################

resource "google_sql_database_instance" "read_replicas" {
  for_each             = var.read_replicas
  name                 = "${var.name}-replica-${each.key}"
  master_instance_name = google_sql_database_instance.instance.name
  database_version     = var.database_version
  region               = coalesce(each.value.region, var.region)
  project              = local.project_id

  settings {
    tier                  = coalesce(each.value.tier, var.tier)
    availability_type     = coalesce(each.value.availability_type, "ZONAL")
    disk_size             = coalesce(each.value.disk_size, var.disk_size)
    disk_type             = coalesce(each.value.disk_type, var.disk_type)
    disk_autoresize       = coalesce(each.value.disk_autoresize, var.disk_autoresize)
    disk_autoresize_limit = coalesce(each.value.disk_autoresize_limit, var.disk_autoresize_limit)
    user_labels           = merge(var.labels, each.value.user_labels)

    ip_configuration {
      ipv4_enabled                                  = false
      private_network                               = local.network_link
      allocated_ip_range                            = var.allocated_ip_range
      enable_private_path_for_google_cloud_services = var.enable_private_path_for_google_cloud_services
      ssl_mode                                      = "ENCRYPTED_ONLY"
    }

    dynamic "location_preference" {
      for_each = each.value.zone != null ? [1] : []
      content {
        zone = each.value.zone
      }
    }

    dynamic "insights_config" {
      for_each = var.query_insights_enabled ? [1] : []
      content {
        query_insights_enabled  = true
        query_string_length     = var.query_string_length
        record_application_tags = var.record_application_tags
        record_client_address   = var.record_client_address
        query_plans_per_minute  = var.query_plans_per_minute
      }
    }

    dynamic "database_flags" {
      for_each = merge(
        local.standard_flags,
        var.database_flags,
        each.value.database_flags,
        { "cloudsql.iam_authentication" = "on" }
      )
      content {
        name  = database_flags.key
        value = database_flags.value
      }
    }
  }

  deletion_protection = var.deletion_protection
  depends_on          = [google_sql_database_instance.instance]
}

###############################################################################
# Databases
###############################################################################

resource "google_sql_database" "databases" {
  for_each  = { for db in var.databases : db.name => db }
  name      = each.value.name
  instance  = google_sql_database_instance.instance.name
  project   = local.project_id
  charset   = each.value.charset
  collation = each.value.collation
}

###############################################################################
# Identity Management: Engineers (Google Account IAM Users)
###############################################################################

resource "google_sql_user" "iam_users" {
  for_each = var.iam_users

  name     = each.value
  instance = google_sql_database_instance.instance.name
  project  = local.project_id
  type     = "CLOUD_IAM_USER"
}

###############################################################################
# Identity Management: Workloads (GKE / CE Service Accounts)
###############################################################################

resource "google_sql_user" "iam_service_accounts" {
  for_each = var.iam_service_accounts

  # Cloud SQL PostgreSQL trims the .gserviceaccount.com suffix for IAM service accounts
  name     = trimsuffix(each.value, ".gserviceaccount.com")
  instance = google_sql_database_instance.instance.name
  project  = local.project_id
  type     = "CLOUD_IAM_SERVICE_ACCOUNT"
}

###############################################################################
# Additional Database Users (Built-in SQL Users)
###############################################################################

resource "google_sql_user" "additional_users" {
  for_each = { for u in var.additional_users : u.name => u }

  name     = each.value.name
  instance = google_sql_database_instance.instance.name
  project  = local.project_id
  password = each.value.password
  type     = each.value.type
}

###############################################################################
# Optional Project-Level IAM Roles for Cloud SQL Access
###############################################################################

resource "google_project_iam_member" "iam_database_access" {
  for_each = {
    for pair in local.iam_role_pairs : "${pair.role}-${pair.member}" => pair
  }

  project = local.project_id
  role    = each.value.role
  member  = each.value.member
}
