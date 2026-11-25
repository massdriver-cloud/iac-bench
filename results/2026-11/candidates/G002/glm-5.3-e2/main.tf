# =============================================================================
# Policy layer
#
# The module separates three kinds of decisions:
#
#   1. Fixed policy — things that must be identical on every instance
#      (private-IP-only connectivity, TLS-only transport, Google-identity
#      logins, deletion protection, backups, standard labels). These are not
#      variables; that is the point.
#   2. Environment policy — standards that differ between dev / staging /
#      prod but are the same for every instance within an environment.
#      Overridable per instance for the rare database that has a reason.
#   3. Per-instance decisions — identity, placement, capacity, databases,
#      flags, users, replicas. These are the DBA team's variables.
# =============================================================================

locals {
  environment_policies = {
    dev = {
      availability_type              = "ZONAL"
      point_in_time_recovery_enabled = false
      query_insights_enabled         = true
    }
    staging = {
      availability_type              = "REGIONAL"
      point_in_time_recovery_enabled = true
      query_insights_enabled         = true
    }
    prod = {
      availability_type              = "REGIONAL"
      point_in_time_recovery_enabled = true
      query_insights_enabled         = true
    }
  }

  policy = local.environment_policies[var.environment]

  # A per-instance override always beats the environment policy; the
  # environment policy is the only default.
  availability_type              = coalesce(var.availability_type, local.policy.availability_type)
  point_in_time_recovery_enabled = coalesce(var.point_in_time_recovery_enabled, local.policy.point_in_time_recovery_enabled)
  query_insights_enabled         = coalesce(var.query_insights_enabled, local.policy.query_insights_enabled)

  # IAM database authentication is the module's authentication standard:
  # every login maps to a Google identity the security team can audit. The
  # flag is merged last so it cannot be turned off by callers.
  database_flags = merge(var.database_flags, { "cloudsql.iam_authentication" = "on" })

  labels = merge(var.labels, {
    environment = var.environment
    managed_by  = "opentofu"
  })

  # Every principal that gets a database login, as a deterministic list of
  # fully typed IAM member identifiers.
  iam_members = distinct(concat(
    [for u in var.iam_users : "user:${u}"],
    [for u in var.iam_service_accounts : "serviceAccount:${u}"],
  ))

  # The roles every database principal needs: the login permission IAM
  # database authentication requires, plus the client permission the Cloud
  # SQL connectors / auth proxy use to discover the instance.
  iam_grant_roles = var.manage_iam_grants ? [
    "roles/cloudsql.instanceUser",
    "roles/cloudsql.client",
  ] : []

  iam_grants = {
    for pair in setproduct(local.iam_members, local.iam_grant_roles) :
    "${pair[0]} ${pair[1]}" => { member = pair[0], role = pair[1] }
  }
}

# -----------------------------------------------------------------------------
# Primary instance
# -----------------------------------------------------------------------------

resource "google_sql_database_instance" "primary" {
  project          = var.project
  name             = var.name
  region           = var.region
  database_version = var.database_version

  # Terraform refuses to destroy the instance while this is set; it pairs
  # with settings.deletion_protection_enabled below so that deleting data is
  # always a deliberate, two-step act. See the README runbook.
  deletion_protection = var.deletion_protection

  # Customer-managed encryption key when requested; Google-managed
  # encryption (null) otherwise.
  encryption_key_name = var.kms_key_name

  settings {
    tier              = var.tier
    edition           = var.edition
    availability_type = local.availability_type

    disk_size       = var.disk_size_gb
    disk_type       = var.disk_type
    disk_autoresize = var.disk_autoresize

    activation_policy           = "ALWAYS"
    deletion_protection_enabled = var.deletion_protection
    user_labels                 = local.labels

    # Backups are always on — that is not a per-instance decision. The
    # window, retention and PITR follow policy and variables.
    backup_configuration {
      enabled                        = true
      start_time                     = var.backup_start_time
      point_in_time_recovery_enabled = local.point_in_time_recovery_enabled

      backup_retention_settings {
        retained_backups = var.backup_retention_days
        retention_unit   = "COUNT"
      }
    }

    # Private connectivity only: no public IPv4 address, ever, and there is
    # no variable for authorized networks. Clients are GKE and Compute
    # Engine workloads inside the environment's VPC; the network team has
    # already configured private services access.
    ip_configuration {
      ipv4_enabled       = false
      private_network    = var.network
      allocated_ip_range = var.allocated_ip_range

      # Plaintext connections are refused; identities are checked at login
      # instead of relying on client certificates.
      ssl_mode = "ENCRYPTED_ONLY"

      # Lets Google-managed services reach the instance over the same
      # private path without ever exposing a public address.
      enable_private_path_for_google_cloud_services = true
    }

    maintenance_window {
      day          = var.maintenance_window.day
      hour         = var.maintenance_window.hour
      update_track = var.maintenance_window.update_track
    }

    dynamic "insights_config" {
      for_each = local.query_insights_enabled ? [1] : []
      content {
        query_insights_enabled  = true
        query_string_length     = 1024
        record_application_tags = true
        record_client_address   = true
      }
    }

    dynamic "database_flags" {
      for_each = local.database_flags
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

  lifecycle {
    precondition {
      condition     = length(setintersection(var.iam_users, var.iam_service_accounts)) == 0
      error_message = "The same identity is listed in both iam_users and iam_service_accounts; list each Google identity exactly once."
    }
  }
}

# -----------------------------------------------------------------------------
# Read replicas
# -----------------------------------------------------------------------------

resource "google_sql_database_instance" "read_replica" {
  for_each = var.read_replicas

  project          = var.project
  name             = each.key
  region           = coalesce(each.value.region, var.region)
  database_version = var.database_version

  master_instance_name = google_sql_database_instance.primary.name
  deletion_protection  = var.deletion_protection

  settings {
    tier    = each.value.tier
    edition = var.edition

    disk_size       = coalesce(each.value.disk_size_gb, var.disk_size_gb)
    disk_type       = coalesce(each.value.disk_type, var.disk_type)
    disk_autoresize = var.disk_autoresize

    deletion_protection_enabled = var.deletion_protection
    user_labels                 = local.labels

    # Same fixed connectivity policy as the primary.
    ip_configuration {
      ipv4_enabled       = false
      private_network    = var.network
      allocated_ip_range = var.allocated_ip_range
      ssl_mode           = "ENCRYPTED_ONLY"

      enable_private_path_for_google_cloud_services = true
    }

    # Replicas carry the same flags as the primary — notably
    # cloudsql.iam_authentication, so logins behave identically there.
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
      condition     = !contains(keys(var.read_replicas), var.name)
      error_message = "A read replica cannot share the primary instance's name."
    }
  }
}
