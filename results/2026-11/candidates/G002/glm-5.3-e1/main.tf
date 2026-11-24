# -----------------------------------------------------------------------------
# Network
#
# The network team owns the environment VPCs (apps-dev, apps-staging,
# apps-prod) and has already set up private services access on each, so the
# only thing this module has to do is attach the instance to the right one.
# A bare network name is resolved in the provider's project; a self link is
# used as-is.
# -----------------------------------------------------------------------------

data "google_compute_network" "selected" {
  count = can(regex("^(https?://|projects/)", var.network)) ? 0 : 1
  name  = var.network
}

# -----------------------------------------------------------------------------
# Primary instance
#
# The settings in this resource are the fleet standard: private IP only,
# TLS required, IAM database authentication only, automated backups with
# point-in-time recovery, regional HA by default, query insights on,
# deletion protection on. The DBA-owned knobs (tier, disk, flags, window,
# ...) are variables; the pinned posture is not.
#
# At rest, Cloud SQL always encrypts the data. With no key supplied the
# Google-managed key is used; with kms_key_name the data is encrypted with
# the security team's Cloud KMS key (CMEK).
# -----------------------------------------------------------------------------

resource "google_sql_database_instance" "primary" {
  name             = var.name
  region           = var.region
  database_version = var.database_version

  # Deletion protection: while this is on, terraform destroy refuses to
  # delete the instance. Disabling it is a deliberate, separate decision.
  deletion_protection = var.deletion_protection

  # Customer-managed encryption, only when a key is supplied.
  encryption_key_name = var.kms_key_name

  settings {
    tier = var.tier

    edition           = var.edition
    availability_type = var.availability_type
    activation_policy = "ALWAYS"

    disk_autoresize       = var.disk_autoresize
    disk_autoresize_limit = var.disk_autoresize_limit
    disk_size             = var.disk_size_gb
    disk_type             = "PD_SSD"

    user_labels = var.labels

    # Automated backups are always on - this is a recovery posture, not a
    # per-instance choice. PITR is on unless the DBAs explicitly say the
    # instance is disposable.
    backup_configuration {
      enabled                        = true
      start_time                     = var.backup_start_time
      point_in_time_recovery_enabled = var.point_in_time_recovery_enabled

      backup_retention_settings {
        retained_backups = var.backup_retention_count
      }
    }

    ip_configuration {
      # Private IP only. Reachability is the environment VPC through the
      # private services access the network team already provisioned. Public
      # IPv4 and authorized networks are deliberately not supported here.
      ipv4_enabled       = false
      private_network    = local.private_network
      ssl_mode           = "ENCRYPTED_ONLY"
      allocated_ip_range = var.allocated_ip_range
    }

    # Query Insights on every instance: the DBA team gets its slow-query
    # telemetry without having to remember to ask for it.
    insights_config {
      query_insights_enabled = true
      query_string_length    = 1024
    }

    maintenance_window {
      day          = local.maintenance_window_day[var.maintenance_window.day]
      hour         = var.maintenance_window.hour
      update_track = var.maintenance_window.update_track
    }

    # DBA flags, merged over the pinned cloudsql.iam_authentication flag.
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
      condition     = alltrue([for name, replica in var.read_replicas : name != var.name])
      error_message = "Read replica names must differ from the primary instance name."
    }

    precondition {
      condition = length(var.iam_database_users) + length(var.iam_database_groups) + length(var.iam_service_accounts) == length(
        distinct(concat(var.iam_database_users, var.iam_database_groups, var.iam_service_accounts))
      )
      error_message = "Each identity may appear at most once across iam_database_users, iam_database_groups and iam_service_accounts."
    }
  }
}

# -----------------------------------------------------------------------------
# Read replicas
#
# Backups, PITR and database flags live on the primary; replicas inherit
# them. Replicas get the same private-IP-only connectivity standard as the
# primary.
# -----------------------------------------------------------------------------

resource "google_sql_database_instance" "read_replicas" {
  for_each = var.read_replicas

  name                 = each.key
  region               = coalesce(each.value.region, var.region)
  database_version     = var.database_version
  master_instance_name = google_sql_database_instance.primary.name
  deletion_protection  = var.deletion_protection

  settings {
    tier = coalesce(each.value.tier, var.tier)

    edition           = var.edition
    availability_type = coalesce(each.value.availability_type, var.availability_type)
    activation_policy = "ALWAYS"

    disk_autoresize       = var.disk_autoresize
    disk_autoresize_limit = var.disk_autoresize_limit
    disk_size             = coalesce(each.value.disk_size_gb, var.disk_size_gb)
    disk_type             = "PD_SSD"

    user_labels = var.labels

    ip_configuration {
      ipv4_enabled       = false
      private_network    = local.private_network
      ssl_mode           = "ENCRYPTED_ONLY"
      allocated_ip_range = var.allocated_ip_range
    }

    maintenance_window {
      day          = local.maintenance_window_day[var.maintenance_window.day]
      hour         = var.maintenance_window.hour
      update_track = var.maintenance_window.update_track
    }
  }
}
