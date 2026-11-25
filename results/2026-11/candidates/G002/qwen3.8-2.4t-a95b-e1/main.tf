###############################################################################
# The instance
#
# Module-owned decisions baked in below:
#   - private IP only, attached to the environment's VPC (no public IP, ever)
#   - TLS required on all connections
#   - IAM database authentication always enabled
#   - automated backups and point-in-time recovery always on
###############################################################################

locals {
  # Flags that are the same on every instance, everywhere. DBA-supplied flags
  # are layered underneath; the module's own flags always win conflicts.
  required_database_flags = {
    "cloudsql.iam_authentication" = "on"
  }
  database_flags = merge(var.database_flags, local.required_database_flags)

  standard_labels = {
    environment = var.environment
    managed-by  = "opentofu"
  }
}

resource "google_sql_database_instance" "this" {
  project             = local.project_id
  name                = var.name
  region              = var.region
  database_version    = "POSTGRES_${var.postgresql_version}"
  deletion_protection = var.deletion_protection

  settings {
    tier                        = var.tier
    edition                     = var.edition
    availability_type           = var.availability_type
    deletion_protection_enabled = var.deletion_protection

    disk_autoresize       = var.disk_autoresize
    disk_autoresize_limit = var.disk_autoresize_limit_gb
    disk_size             = var.disk_size_gb
    disk_type             = var.disk_type

    user_labels = merge(local.standard_labels, var.user_labels)

    dynamic "database_flags" {
      for_each = local.database_flags
      content {
        name  = database_flags.key
        value = database_flags.value
      }
    }

    ip_configuration {
      ipv4_enabled       = false
      private_network    = local.network_self_link
      allocated_ip_range = var.allocated_ip_range
      ssl_mode           = "ENCRYPTED_ONLY"
    }

    backup_configuration {
      enabled                        = true
      start_time                     = var.backup_start_time
      point_in_time_recovery_enabled = true
      transaction_log_retention_days = var.transaction_log_retention_days

      backup_retention_settings {
        retained_backups = var.backup_retention_days
      }
    }

    maintenance_window {
      day          = var.maintenance_window.day
      hour         = var.maintenance_window.hour
      update_track = var.maintenance_window.update_track
    }

    dynamic "location_preference" {
      for_each = var.zone != null ? [var.zone] : []
      content {
        zone = location_preference.value
      }
    }
  }
}

###############################################################################
# Access: IAM-authenticated users and databases
#
# Every identity in var.iam_users becomes a Cloud SQL IAM database user AND
# is granted roles/cloudsql.instanceUser, which is what lets the identity
# actually connect with IAM authentication (from GKE, Compute Engine or the
# Cloud SQL Auth Proxy). Access stays attributable to a Google identity end
# to end — no shared passwords exist.
###############################################################################

locals {
  # Normalise identities into a Cloud SQL user type and an IAM member.
  iam_users = {
    for email in var.iam_users :
    email => {
      sql_user_type = endswith(email, ".gserviceaccount.com") ? "CLOUD_IAM_SERVICE_ACCOUNT" : "CLOUD_IAM_USER"
      member        = endswith(email, ".gserviceaccount.com") ? "serviceAccount:${email}" : "user:${email}"
    }
  }
}

resource "google_sql_user" "iam_users" {
  for_each = local.iam_users

  project  = local.project_id
  instance = google_sql_database_instance.this.name
  name     = each.key
  type     = each.value.sql_user_type
}

resource "google_project_iam_member" "instance_user" {
  # The provider has no instance-scoped IAM resource for Cloud SQL, so the
  # connect role is granted at project scope. Projects running this module
  # are expected to host databases, so the scope is acceptable; set
  # grant_instance_user_role = false if the security team manages these
  # grants out of band instead.
  for_each = var.grant_instance_user_role ? local.iam_users : {}

  project = local.project_id
  role    = "roles/cloudsql.instanceUser"
  member  = each.value.member
}

resource "google_sql_database" "databases" {
  for_each = toset(var.databases)

  project  = local.project_id
  instance = google_sql_database_instance.this.name
  name     = each.value
}
