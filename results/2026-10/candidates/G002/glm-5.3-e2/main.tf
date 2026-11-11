###############################################################################
# Locals
###############################################################################

locals {
  # The network team owns the VPCs; resolve whatever they hand us (a bare
  # network name in its own project, or a full self link) to a self link.
  network_project = coalesce(var.network_project_id, var.project_id)

  network_self_link = (
    can(regex("^(projects/|https://)", var.network))
    ? var.network
    : "projects/${local.network_project}/global/networks/${var.network}"
  )

  # One label set for every instance this module manages.
  user_labels = merge(var.user_labels, { "managed-by" = "opentofu" })
}

###############################################################################
# Primary instance
###############################################################################

resource "google_sql_database_instance" "primary" {
  project          = var.project_id
  name             = var.name
  region           = var.region
  database_version = var.database_version

  # Refuse to destroy a database through Terraform; the same switch enables
  # the API-level protection so the console cannot delete it either.
  deletion_protection = var.deletion_protection

  settings {
    tier              = var.tier
    edition           = var.edition
    availability_type = var.availability_type

    disk_size             = var.disk_size
    disk_type             = var.disk_type
    disk_autoresize       = var.disk_autoresize
    disk_autoresize_limit = var.disk_autoresize_limit

    deletion_protection_enabled = var.deletion_protection

    user_labels = local.user_labels

    dynamic "location_preference" {
      for_each = var.zone == null ? [] : [var.zone]
      content {
        zone = location_preference.value
      }
    }

    maintenance_window {
      day  = var.maintenance_window_day
      hour = var.maintenance_window_hour
    }

    insights_config {
      query_insights_enabled  = var.query_insights_enabled
      query_string_length     = 1024
      record_client_address   = true
      record_application_tags = true
    }

    # Private services access only: no public IP, no authorized networks.
    # Clients are GKE and Compute Engine workloads in the same network,
    # connecting over TLS and authenticating with their Google identity.
    ip_configuration {
      ipv4_enabled       = false
      private_network    = local.network_self_link
      ssl_mode           = "ENCRYPTED_ONLY"
      allocated_ip_range = var.allocated_ip_range
    }

    # Backups are not optional.
    backup_configuration {
      enabled                        = true
      start_time                     = var.backup_start_time
      point_in_time_recovery_enabled = var.point_in_time_recovery_enabled
      transaction_log_retention_days = var.transaction_log_retention_days

      backup_retention_settings {
        retained_backups = var.backup_retention_count
        retention_unit   = "COUNT"
      }
    }

    dynamic "database_flags" {
      for_each = var.database_flags
      content {
        name  = database_flags.key
        value = database_flags.value
      }
    }
  }
}
