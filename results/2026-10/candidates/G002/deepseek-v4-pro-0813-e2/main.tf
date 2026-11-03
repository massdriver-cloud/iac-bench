# ---------------------------------------------------------------------------
# Cloud SQL for PostgreSQL — standard instance for the DBA team.
#
# Fixed, non-negotiable security/operational posture:
#   * Private IP only (no public IP), attached to the environment VPC that
#     already has private services access configured by the network team.
#   * IAM-based authentication only (user + serviceaccount identities).
#   * TLS required for all connections.
#   * Automated backups with point-in-time recovery, deletion protection on.
# ---------------------------------------------------------------------------

locals {
  network_project = var.network_project_id != null ? var.network_project_id : var.project_id

  # A db-custom tier derived from cpu/memory is a single, standard choice;
  # the DBA team can still pin an explicit tier when they need something exotic.
  computed_tier     = var.tier != null ? var.tier : "db-custom-${var.cpu}-${var.memory_mb}"
  replica_tier      = var.replica_tier != null ? var.replica_tier : local.computed_tier
  network_self_link = "projects/${local.network_project}/global/networks/${var.network_name}"

  labels = merge(
    {
      managed-by = "tofu"
      owner-team = var.owner_team
      service    = "postgres"
      database   = var.name
    },
    var.environment != null ? { environment = var.environment } : {},
    var.additional_labels,
  )

  database_flags = [
    { name = "log_min_duration_statement", value = "1000" },
    { name = "log_connections", value = "on" },
    { name = "log_disconnections", value = "on" },
  ]

  # Flatten iam_users into a set of {principal, type} for user creation,
  # de-duplicating principals that are authorized on multiple databases.
  iam_users_flat = {
    for principal in distinct(flatten([
      for db, principals in var.iam_users : principals
    ])) :
    principal => {
      principal = principal
      type      = startswith(principal, "serviceAccount:") ? "CLOUD_IAM_SERVICE_ACCOUNT" : "CLOUD_IAM_USER"
    }
  }
}

resource "google_sql_database_instance" "primary" {
  name                = var.name
  project             = var.project_id
  region              = var.region
  database_version    = var.postgres_version
  deletion_protection = var.deletion_protection

  settings {
    tier                  = local.computed_tier
    edition               = "ENTERPRISE"
    availability_type     = var.availability_type
    disk_type             = var.disk_type
    disk_size             = var.disk_size_gb
    disk_autoresize       = var.disk_autoresize
    disk_autoresize_limit = var.disk_autoresize_limit_gb > 0 ? var.disk_autoresize_limit_gb : null
    user_labels           = local.labels

    maintenance_window {
      day          = var.maintenance_day
      hour         = var.maintenance_hour
      update_track = "stable"
    }

    insights_config {
      query_insights_enabled  = var.query_insights_enabled
      query_string_length     = 1024
      record_application_tags = true
      record_client_address   = false
    }

    backup_configuration {
      enabled                        = var.backup_enabled
      start_time                     = var.backup_start_time
      point_in_time_recovery_enabled = var.point_in_time_recovery
      transaction_log_retention_days = var.transaction_log_retention_days
      backup_retention_settings {
        retained_backups = var.backup_retention_days
      }
    }

    ip_configuration {
      ipv4_enabled    = var.ipv4_enabled
      private_network = local.network_self_link
      ssl_mode        = "ENCRYPTED_ONLY"
    }

    dynamic "database_flags" {
      for_each = local.database_flags
      content {
        name  = database_flags.value.name
        value = database_flags.value.value
      }
    }

    # Optional preferred zone for ZONAL instances keeps placement explicit.
    dynamic "location_preference" {
      for_each = var.zone != null && var.availability_type == "ZONAL" ? [1] : []
      content {
        zone = var.zone
      }
    }
  }

  lifecycle {
    prevent_destroy = var.deletion_protection
  }
}

# ---------------------------------------------------------------------------
# Read replicas
# ---------------------------------------------------------------------------

resource "google_sql_database_instance" "replica" {
  count = var.replica_count

  name                 = "${var.name}-replica-${count.index + 1}"
  project              = var.project_id
  region               = var.region
  database_version     = var.postgres_version
  master_instance_name = google_sql_database_instance.primary.name
  deletion_protection  = var.deletion_protection

  settings {
    tier                  = local.replica_tier
    edition               = "ENTERPRISE"
    disk_type             = var.disk_type
    disk_size             = var.disk_size_gb
    disk_autoresize       = var.disk_autoresize
    disk_autoresize_limit = var.disk_autoresize_limit_gb > 0 ? var.disk_autoresize_limit_gb : null
    user_labels           = local.labels

    ip_configuration {
      ipv4_enabled    = var.ipv4_enabled
      private_network = local.network_self_link
      ssl_mode        = "ENCRYPTED_ONLY"
    }

    dynamic "location_preference" {
      for_each = length(var.replica_zones) > count.index ? [1] : []
      content {
        zone = var.replica_zones[count.index]
      }
    }
  }

  lifecycle {
    prevent_destroy = var.deletion_protection
  }
}

# ---------------------------------------------------------------------------
# Databases
# ---------------------------------------------------------------------------

resource "google_sql_database" "db" {
  for_each = var.databases

  name     = each.key
  instance = google_sql_database_instance.primary.name
  project  = var.project_id
  charset  = each.value
}

# ---------------------------------------------------------------------------
# IAM users — every engineer/workload already has a Google identity and the
# security team audits access by identity. We therefore create only IAM users,
# never password users. The database-level GRANT for each principal is emitted
# as SQL (output "iam_grants_sql") and applied once by the DBA, because Cloud
# SQL IAM privileges can only be granted over a database connection.
# ---------------------------------------------------------------------------

resource "google_sql_user" "iam" {
  for_each = local.iam_users_flat

  name     = each.value.principal
  instance = google_sql_database_instance.primary.name
  project  = var.project_id
  type     = each.value.type
}