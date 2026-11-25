locals {
  flags = merge(var.database_flags, { "cloudsql.iam_authentication" = "on" })
  identity_roles = {
    for pair in setproduct(keys(var.iam_identities), ["roles/cloudsql.client", "roles/cloudsql.instanceUser"]) :
    "${pair[0]} ${pair[1]}" => {
      member = "${var.iam_identities[pair[0]] == "SERVICE_ACCOUNT" ? "serviceAccount" : "user"}:${pair[0]}"
      role   = pair[1]
    }
  }
}

resource "google_sql_database_instance" "this" {
  project             = var.project_id
  name                = var.name
  region              = var.region
  database_version    = var.postgres_version
  deletion_protection = var.deletion_protection

  settings {
    edition                     = "ENTERPRISE"
    tier                        = var.tier
    availability_type           = var.availability_type
    activation_policy           = "ALWAYS"
    disk_type                   = "PD_SSD"
    disk_size                   = var.disk_size_gb
    disk_autoresize             = true
    deletion_protection_enabled = var.deletion_protection
    connector_enforcement       = "REQUIRED"
    user_labels                 = var.labels

    ip_configuration {
      ipv4_enabled    = false
      private_network = var.network
      ssl_mode        = "ENCRYPTED_ONLY"
    }

    backup_configuration {
      enabled                        = true
      start_time                     = var.backup_start_time
      point_in_time_recovery_enabled = true
      transaction_log_retention_days = 7
      backup_retention_settings {
        retained_backups = 14
        retention_unit   = "COUNT"
      }
    }

    maintenance_window {
      day          = var.maintenance_window.day
      hour         = var.maintenance_window.hour
      update_track = "stable"
    }

    dynamic "database_flags" {
      for_each = local.flags
      content {
        name  = database_flags.key
        value = database_flags.value
      }
    }
  }
}

resource "google_sql_database" "application" {
  for_each  = var.database_names
  project   = var.project_id
  instance  = google_sql_database_instance.this.name
  name      = each.value
  charset   = "UTF8"
  collation = "en_US.UTF8"
}

resource "google_project_iam_member" "connection" {
  for_each = local.identity_roles
  project  = var.project_id
  role     = each.value.role
  member   = each.value.member
}

resource "google_sql_user" "iam" {
  for_each = var.iam_identities
  project  = var.project_id
  instance = google_sql_database_instance.this.name
  name     = each.value == "SERVICE_ACCOUNT" ? trimsuffix(each.key, ".gserviceaccount.com") : each.key
  type     = each.value == "SERVICE_ACCOUNT" ? "CLOUD_IAM_SERVICE_ACCOUNT" : "CLOUD_IAM_USER"

  depends_on = [google_project_iam_member.connection]
}
