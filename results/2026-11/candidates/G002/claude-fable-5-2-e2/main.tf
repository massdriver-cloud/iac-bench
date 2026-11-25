###############################################################################
# Standard PostgreSQL on Cloud SQL
#
# Fixed by this module (the same on every instance):
#   - private IP only, on the environment's application VPC (apps-<env>),
#     using the private services access the network team already provides
#   - TLS required on every connection
#   - IAM database authentication; the module creates no password users
#   - connection logging and pgAudit, so access is attributable to identities
#   - daily backups + point-in-time recovery, backups kept if the instance goes
#   - deletion protection, storage auto-grow, Query Insights, standard labels
#
# Left to the DBAs (variables): version, edition, machine size, HA, storage,
# tuning flags, replicas, databases, who may log in, backup/maintenance timing.
###############################################################################

data "google_client_config" "current" {
  count = var.project_id == null ? 1 : 0
}

locals {
  project_id         = var.project_id != null ? var.project_id : one(data.google_client_config.current[*].project)
  network_project_id = var.network_project_id != null ? var.network_project_id : local.project_id

  # One application VPC per environment, owned by the network team. It is
  # referenced, never created or modified, and so is its private services
  # access peering.
  network_name    = "apps-${var.environment}"
  private_network = "projects/${local.network_project_id}/global/networks/${local.network_name}"

  is_prod       = var.environment == "prod"
  instance_name = "${var.name}-${var.environment}"

  availability_type = coalesce(var.availability_type, local.is_prod ? "REGIONAL" : "ZONAL")
  update_track      = coalesce(var.maintenance_window.update_track, local.is_prod ? "stable" : "canary")

  # Flag precedence, lowest to highest: logging defaults < DBA flags < enforced.
  default_database_flags = {
    "log_checkpoints" = "on"
    "log_lock_waits"  = "on"
    "log_temp_files"  = "0"
    # What pgAudit records. DDL and role/privilege changes by default; DBAs can
    # widen it (e.g. "ddl,role,write" or "all") per instance.
    "pgaudit.log" = "ddl,role"
  }

  enforced_database_flags = {
    # Logins are authenticated against Google identities.
    "cloudsql.iam_authentication" = "on"
    # Every session start/end is logged with the identity that opened it.
    "log_connections"    = "on"
    "log_disconnections" = "on"
    # Statement-level audit trail (run CREATE EXTENSION pgaudit once per database).
    "cloudsql.enable_pgaudit" = "on"
  }

  database_flags = merge(local.default_database_flags, var.database_flags, local.enforced_database_flags)

  labels = merge(var.labels, {
    environment = var.environment
    database    = var.name
    managed-by  = "opentofu"
  })

  # "user:alice@example.com" -> database user "alice@example.com"
  # "group:dbas@example.com" -> database user "dbas@example.com"
  # "serviceAccount:app@p.iam.gserviceaccount.com" -> database user "app@p.iam"
  iam_user_types = {
    user           = "CLOUD_IAM_USER"
    group          = "CLOUD_IAM_GROUP"
    serviceAccount = "CLOUD_IAM_SERVICE_ACCOUNT"
  }

  iam_users = {
    for m in var.iam_members : m => {
      type     = local.iam_user_types[split(":", m)[0]]
      username = trimsuffix(split(":", m)[1], ".gserviceaccount.com")
    }
  }

  # roles/cloudsql.client       - connect (Auth Proxy / connectors)
  # roles/cloudsql.instanceUser - log in with IAM database authentication
  iam_roles = ["roles/cloudsql.client", "roles/cloudsql.instanceUser"]

  iam_grants = {
    for pair in setproduct(var.iam_members, local.iam_roles) :
    "${pair[0]} ${pair[1]}" => { member = pair[0], role = pair[1] }
  }

  replica_name_prefix = "${local.instance_name}-replica-"
  replica_names       = { for k, v in var.read_replicas : k => "${local.replica_name_prefix}${k}" }

  # The roles are granted at project level (Cloud SQL has no per-instance IAM
  # policy) but conditioned to this instance and its replicas only. Replicas
  # are matched by name prefix so that adding or removing one never touches
  # (and briefly interrupts) existing grants.
  iam_instance_path = "projects/${local.project_id}/instances/${local.instance_name}"
  iam_condition_expression = join(" && ", [
    "resource.type == \"sqladmin.googleapis.com/Instance\"",
    "(resource.name == \"${local.iam_instance_path}\" || resource.name.startsWith(\"${local.iam_instance_path}-replica-\"))",
  ])
}

###############################################################################
# Primary instance
###############################################################################

resource "google_sql_database_instance" "primary" {
  project          = local.project_id
  name             = local.instance_name
  region           = var.region
  database_version = var.database_version

  encryption_key_name = var.encryption_key_name
  deletion_protection = var.deletion_protection

  settings {
    edition           = var.edition
    tier              = var.tier
    availability_type = local.availability_type

    disk_type             = "PD_SSD"
    disk_size             = var.disk_size_gb
    disk_autoresize       = true
    disk_autoresize_limit = var.disk_autoresize_limit_gb

    deletion_protection_enabled = var.deletion_protection
    retain_backups_on_delete    = true

    connector_enforcement = var.require_cloud_sql_connectors ? "REQUIRED" : "NOT_REQUIRED"

    user_labels = local.labels

    ip_configuration {
      ipv4_enabled       = false
      private_network    = local.private_network
      allocated_ip_range = var.allocated_ip_range
      ssl_mode           = var.ssl_mode
    }

    backup_configuration {
      enabled                        = true
      start_time                     = var.backup.start_time
      location                       = var.backup.location
      point_in_time_recovery_enabled = true
      transaction_log_retention_days = var.backup.transaction_log_retention_days

      backup_retention_settings {
        retained_backups = var.backup.retained_backups
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
      query_string_length     = 2048
      query_plans_per_minute  = 5
      record_application_tags = true
      record_client_address   = true
    }

    # The module creates no password users. Should a DBA ever set a password
    # out of band (break-glass on the built-in postgres user), it must be strong.
    password_validation_policy {
      enable_password_policy      = true
      min_length                  = 20
      complexity                  = "COMPLEXITY_DEFAULT"
      disallow_username_substring = true
    }

    dynamic "location_preference" {
      for_each = var.zone == null ? [] : [var.zone]
      content {
        zone = location_preference.value
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
    # Storage auto-grow changes the real size; never try to shrink it back.
    ignore_changes = [settings[0].disk_size]

    precondition {
      condition     = local.project_id != null && local.project_id != ""
      error_message = "No project could be determined. Set project_id or configure a default project for the Google provider (e.g. GOOGLE_PROJECT)."
    }

    precondition {
      condition     = var.edition == "ENTERPRISE_PLUS" ? startswith(var.tier, "db-perf-optimized-") : !startswith(var.tier, "db-perf-optimized-")
      error_message = "tier does not match edition: ENTERPRISE_PLUS needs a db-perf-optimized-N-* tier, ENTERPRISE needs a db-custom-* (or shared-core) tier."
    }

    precondition {
      condition     = var.edition == "ENTERPRISE_PLUS" || var.backup.transaction_log_retention_days <= 7
      error_message = "backup.transaction_log_retention_days cannot exceed 7 on the ENTERPRISE edition (35 on ENTERPRISE_PLUS)."
    }

    precondition {
      condition     = var.disk_autoresize_limit_gb == 0 || var.disk_autoresize_limit_gb >= var.disk_size_gb
      error_message = "disk_autoresize_limit_gb must be 0 (no limit) or at least disk_size_gb."
    }

    precondition {
      condition     = var.zone == null ? true : startswith(var.zone, "${var.region}-")
      error_message = "zone must be a zone of region."
    }
  }
}

###############################################################################
# Read replicas - same standard as the primary
###############################################################################

resource "google_sql_database_instance" "replica" {
  for_each = var.read_replicas

  project              = local.project_id
  name                 = local.replica_names[each.key]
  region               = coalesce(each.value.region, var.region)
  database_version     = var.database_version
  master_instance_name = google_sql_database_instance.primary.name

  encryption_key_name = each.value.encryption_key_name != null ? each.value.encryption_key_name : var.encryption_key_name
  deletion_protection = var.deletion_protection

  settings {
    edition           = var.edition
    tier              = coalesce(each.value.tier, var.tier)
    availability_type = "ZONAL"

    disk_type             = "PD_SSD"
    disk_autoresize       = true
    disk_autoresize_limit = var.disk_autoresize_limit_gb

    deletion_protection_enabled = var.deletion_protection

    connector_enforcement = var.require_cloud_sql_connectors ? "REQUIRED" : "NOT_REQUIRED"

    user_labels = merge(local.labels, { replica-of = local.instance_name })

    ip_configuration {
      ipv4_enabled       = false
      private_network    = local.private_network
      allocated_ip_range = var.allocated_ip_range
      ssl_mode           = var.ssl_mode
    }

    insights_config {
      query_insights_enabled  = true
      query_string_length     = 2048
      query_plans_per_minute  = 5
      record_application_tags = true
      record_client_address   = true
    }

    dynamic "location_preference" {
      for_each = each.value.zone == null ? [] : [each.value.zone]
      content {
        zone = location_preference.value
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
    ignore_changes = [settings[0].disk_size]

    precondition {
      condition     = var.encryption_key_name == null || each.value.encryption_key_name != null || coalesce(each.value.region, var.region) == var.region
      error_message = "A cross-region replica of a CMEK-encrypted primary needs its own encryption_key_name in the replica's region."
    }

    precondition {
      condition     = each.value.zone == null ? true : startswith(each.value.zone, "${coalesce(each.value.region, var.region)}-")
      error_message = "The replica's zone must be a zone of its region."
    }
  }
}

###############################################################################
# Databases
###############################################################################

resource "google_sql_database" "this" {
  for_each = var.databases

  project   = local.project_id
  instance  = google_sql_database_instance.primary.name
  name      = each.key
  charset   = each.value.charset
  collation = each.value.collation

  # Dropping a database is a deliberate DBA action in SQL, never a side effect
  # of editing a map: removal from configuration only stops managing it.
  deletion_policy = "ABANDON"
}

###############################################################################
# Access: Google identities only
###############################################################################

resource "google_sql_user" "iam" {
  for_each = local.iam_users

  project  = local.project_id
  instance = google_sql_database_instance.primary.name
  name     = each.value.username
  type     = each.value.type
}

resource "google_project_iam_member" "database_access" {
  for_each = local.iam_grants

  project = local.project_id
  role    = each.value.role
  member  = each.value.member

  condition {
    title       = "cloud-sql-${local.instance_name}"
    description = "Limited to Cloud SQL instance ${local.instance_name} and its replicas. Managed by OpenTofu."
    expression  = local.iam_condition_expression
  }
}
