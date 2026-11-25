resource "google_sql_database_instance" "read_replica" {
  for_each = var.read_replicas

  name                 = "${var.name}-${each.key}"
  project              = local.project_id
  region               = coalesce(each.value.region, local.region)
  database_version     = var.database_version
  master_instance_name = google_sql_database_instance.primary.name
  deletion_protection  = each.value.deletion_protection != null ? each.value.deletion_protection : local.deletion_protection
  encryption_key_name  = each.value.encryption_key_name != null ? each.value.encryption_key_name : var.encryption_key_name

  settings {
    tier                        = coalesce(each.value.tier, var.tier)
    edition                     = var.edition
    availability_type           = each.value.availability_type
    disk_type                   = coalesce(each.value.disk_type, var.disk_type)
    disk_autoresize             = true
    disk_autoresize_limit       = coalesce(each.value.disk_autoresize_limit_gb, var.disk_autoresize_limit_gb)
    deletion_protection_enabled = each.value.deletion_protection != null ? each.value.deletion_protection : local.deletion_protection
    connector_enforcement       = var.connector_enforcement

    user_labels = merge(
      var.labels,
      each.value.labels,
      local.standard_labels,
      {
        role = "read-replica"
      },
    )

    ip_configuration {
      ipv4_enabled                                  = false
      private_network                               = data.google_compute_network.vpc.id
      allocated_ip_range                            = var.allocated_ip_range
      enable_private_path_for_google_cloud_services = true
      ssl_mode                                      = "ENCRYPTED_ONLY"
    }

    insights_config {
      query_insights_enabled  = true
      query_string_length     = var.query_insights.query_string_length
      query_plans_per_minute  = var.query_insights.query_plans_per_minute
      record_application_tags = var.query_insights.record_application_tags
      record_client_address   = var.query_insights.record_client_address
    }

    dynamic "location_preference" {
      for_each = each.value.zone != null ? [each.value.zone] : []
      content {
        zone = location_preference.value
      }
    }

    dynamic "data_cache_config" {
      for_each = var.edition == "ENTERPRISE_PLUS" ? [1] : []
      content {
        data_cache_enabled = var.data_cache_enabled
      }
    }

    password_validation_policy {
      enable_password_policy      = true
      min_length                  = 16
      complexity                  = "COMPLEXITY_DEFAULT"
      reuse_interval              = 5
      disallow_username_substring = true
    }

    dynamic "database_flags" {
      for_each = merge(
        local.primary_database_flags,
        each.value.database_flags,
        local.mandatory_security_flags,
      )
      content {
        name  = database_flags.key
        value = database_flags.value
      }
    }
  }

  lifecycle {
    ignore_changes = [
      settings[0].disk_size,
    ]
  }
}
