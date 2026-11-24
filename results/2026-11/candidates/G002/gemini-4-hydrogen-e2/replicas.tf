resource "google_sql_database_instance" "read_replicas" {
  for_each = var.read_replicas

  name                 = "${local.instance_name}-ro-${each.key}"
  master_instance_name = google_sql_database_instance.primary.name
  region               = coalesce(each.value.region, var.region)
  database_version     = var.database_version
  deletion_protection  = coalesce(each.value.deletion_protection, var.deletion_protection)

  settings {
    tier                        = coalesce(each.value.tier, local.tier)
    edition                     = var.edition
    availability_type           = each.value.availability_type
    activation_policy           = "ALWAYS"
    disk_type                   = "PD_SSD"
    disk_size                   = coalesce(each.value.disk_size, local.disk_size)
    disk_autoresize             = true
    disk_autoresize_limit       = coalesce(each.value.disk_autoresize_limit, var.disk_autoresize_limit)
    deletion_protection_enabled = coalesce(each.value.deletion_protection, var.deletion_protection)
    connector_enforcement       = local.connector_enforcement
    user_labels = merge(local.labels, {
      role    = "read-replica"
      replica = each.key
    })

    ip_configuration {
      ipv4_enabled                                  = false
      private_network                               = data.google_compute_network.vpc.id
      allocated_ip_range                            = var.allocated_ip_range
      enable_private_path_for_google_cloud_services = true
      ssl_mode                                      = local.ssl_mode
    }

    maintenance_window {
      day          = coalesce(each.value.maintenance_window.day, 7)
      hour         = coalesce(each.value.maintenance_window.hour, 4)
      update_track = coalesce(each.value.maintenance_window.update_track, local.maintenance_update_track)
    }

    insights_config {
      query_insights_enabled  = true
      query_plans_per_minute  = 5
      query_string_length     = 2048
      record_application_tags = true
      record_client_address   = true
    }

    dynamic "database_flags" {
      for_each = merge(
        local.default_database_flags,
        each.value.database_flags,
        local.mandatory_database_flags,
      )
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
