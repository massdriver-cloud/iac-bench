###############################################################################
# Read replicas
#
# Replicas inherit the module's standards (private IP only, TLS required) and
# default to the primary's shape; anything the DBA team overrides is
# per replica.
###############################################################################

resource "google_sql_database_instance" "replicas" {
  for_each = var.replicas

  project              = var.project_id
  name                 = "${var.name}-${each.key}"
  region               = coalesce(each.value.region, var.region)
  database_version     = var.database_version
  master_instance_name = google_sql_database_instance.primary.name

  deletion_protection = var.deletion_protection

  settings {
    tier              = coalesce(each.value.tier, var.tier)
    edition           = var.edition
    availability_type = each.value.availability_type

    disk_size             = coalesce(each.value.disk_size, var.disk_size)
    disk_type             = coalesce(each.value.disk_type, var.disk_type)
    disk_autoresize       = var.disk_autoresize
    disk_autoresize_limit = var.disk_autoresize_limit

    user_labels = local.user_labels

    dynamic "location_preference" {
      for_each = each.value.zone == null ? [] : [each.value.zone]
      content {
        zone = location_preference.value
      }
    }

    ip_configuration {
      ipv4_enabled       = false
      private_network    = local.network_self_link
      ssl_mode           = "ENCRYPTED_ONLY"
      allocated_ip_range = var.allocated_ip_range
    }
  }
}
