data "google_project" "current" {}

data "google_compute_network" "vpc" {
  name = local.vpc_name
}

resource "google_sql_database_instance" "primary" {
  name                = local.instance_name
  region              = var.region
  database_version    = var.database_version
  deletion_protection = var.deletion_protection

  settings {
    tier                        = local.tier
    edition                     = var.edition
    availability_type           = local.availability_type
    activation_policy           = "ALWAYS"
    disk_type                   = "PD_SSD"
    disk_size                   = local.disk_size
    disk_autoresize             = true
    disk_autoresize_limit       = var.disk_autoresize_limit
    deletion_protection_enabled = var.deletion_protection
    connector_enforcement       = local.connector_enforcement
    user_labels                 = local.labels

    ip_configuration {
      ipv4_enabled                                  = false
      private_network                               = data.google_compute_network.vpc.id
      allocated_ip_range                            = var.allocated_ip_range
      enable_private_path_for_google_cloud_services = true
      ssl_mode                                      = local.ssl_mode
    }

    backup_configuration {
      enabled                        = true
      point_in_time_recovery_enabled = true
      start_time                     = local.backup_start_time
      location                       = var.backup_configuration.location
      transaction_log_retention_days = local.transaction_log_retention_days

      backup_retention_settings {
        retention_unit   = "COUNT"
        retained_backups = local.retained_backups
      }
    }

    maintenance_window {
      day          = local.maintenance_day
      hour         = local.maintenance_hour
      update_track = local.maintenance_update_track
    }

    insights_config {
      query_insights_enabled  = true
      query_plans_per_minute  = 5
      query_string_length     = 2048
      record_application_tags = true
      record_client_address   = true
    }

    dynamic "database_flags" {
      for_each = local.effective_database_flags
      content {
        name  = database_flags.key
        value = database_flags.value
      }
    }
  }

  lifecycle {
    # Prevent plan errors if Cloud SQL disk_autoresize expands storage beyond the initial disk_size,
    # as Cloud SQL does not allow shrinking disks.
    ignore_changes = [settings[0].disk_size]
  }
}

resource "google_sql_database" "databases" {
  for_each = var.databases

  name            = each.key
  instance        = google_sql_database_instance.primary.name
  charset         = each.value.charset
  collation       = each.value.collation
  deletion_policy = each.value.deletion_policy
}
