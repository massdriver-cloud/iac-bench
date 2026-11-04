locals {
  network_project_id = coalesce(var.network_project_id, var.project_id)
  private_network    = "projects/${local.network_project_id}/global/networks/apps-${var.environment}"
  identity_types = {
    USER            = "CLOUD_IAM_USER"
    SERVICE_ACCOUNT = "CLOUD_IAM_SERVICE_ACCOUNT"
    GROUP           = "CLOUD_IAM_GROUP"
  }
  member_prefixes = {
    USER            = "user"
    SERVICE_ACCOUNT = "serviceAccount"
    GROUP           = "group"
  }
  access_grants = { for grant in flatten([
    for email, kind in var.iam_members : [
      for role in ["roles/cloudsql.client", "roles/cloudsql.instanceUser"] : {
        key    = "${email}/${role}"
        member = "${local.member_prefixes[kind]}:${email}"
        role   = role
      }
    ]
  ]) : grant.key => grant }
}

resource "google_sql_database_instance" "postgres" {
  project             = var.project_id
  name                = var.instance_name
  region              = var.region
  database_version    = var.database_version
  deletion_protection = var.deletion_protection

  settings {
    edition                     = "ENTERPRISE"
    tier                        = var.tier
    availability_type           = var.availability_type
    activation_policy           = "ALWAYS"
    disk_type                   = "PD_SSD"
    disk_size                   = var.disk_size_gb
    disk_autoresize             = true
    disk_autoresize_limit       = var.disk_autoresize_limit_gb
    deletion_protection_enabled = var.deletion_protection
    user_labels = merge(var.labels, {
      environment = var.environment
      managed_by  = "opentofu"
    })

    ip_configuration {
      ipv4_enabled                                  = false
      private_network                               = local.private_network
      ssl_mode                                      = "ENCRYPTED_ONLY"
      enable_private_path_for_google_cloud_services = false
    }

    backup_configuration {
      enabled                        = true
      point_in_time_recovery_enabled = true
      start_time                     = var.backup_start_time
      location                       = var.backup_location
      transaction_log_retention_days = var.transaction_log_retention_days
      backup_retention_settings {
        retained_backups = var.retained_backups
        retention_unit   = "COUNT"
      }
    }

    maintenance_window {
      day          = var.maintenance_window.day
      hour         = var.maintenance_window.hour
      update_track = var.maintenance_window.update_track
    }

    dynamic "database_flags" {
      for_each = merge(var.database_flags, {
        "cloudsql.iam_authentication" = "on"
        "log_connections"             = "on"
        "log_disconnections"          = "on"
      })
      content {
        name  = database_flags.key
        value = database_flags.value
      }
    }
  }

  lifecycle {
    precondition {
      condition     = var.disk_autoresize_limit_gb == 0 || var.disk_autoresize_limit_gb >= var.disk_size_gb
      error_message = "Automatic disk growth ceiling must be zero (unlimited) or at least the initial disk size."
    }
  }
}

resource "google_sql_database" "databases" {
  for_each  = var.databases
  project   = var.project_id
  instance  = google_sql_database_instance.postgres.name
  name      = each.key
  charset   = each.value.charset
  collation = each.value.collation
}

resource "google_sql_user" "iam" {
  for_each = var.iam_members
  project  = var.project_id
  instance = google_sql_database_instance.postgres.name
  name     = each.value == "SERVICE_ACCOUNT" ? trimsuffix(each.key, ".gserviceaccount.com") : each.key
  type     = local.identity_types[each.value]
}

# Non-authoritative additions: never replace the project's existing IAM policy.
# Conditions prevent these grants from authorizing access to other instances.
resource "google_project_iam_member" "database_access" {
  for_each = local.access_grants
  project  = var.project_id
  role     = each.value.role
  member   = each.value.member

  condition {
    title       = "cloudsql-${var.instance_name}"
    description = "Access only to the ${var.instance_name} Cloud SQL instance"
    expression  = "resource.name == 'projects/${var.project_id}/instances/${google_sql_database_instance.postgres.name}' && resource.type == 'sqladmin.googleapis.com/Instance'"
  }
}
