resource "google_sql_database_instance" "this" {
  project          = var.project_id
  name             = var.instance_name
  region           = var.region
  database_version = var.database_version

  deletion_protection = var.deletion_protection

  settings {
    tier                  = var.tier
    edition               = var.edition
    availability_type     = local.availability_type
    activation_policy     = "ALWAYS"
    pricing_plan          = "PER_USE"
    disk_type             = var.disk_type
    disk_size             = var.disk_size_gb
    disk_autoresize       = true
    disk_autoresize_limit = var.disk_autoresize_limit_gb
    user_labels           = merge(var.labels, local.standard_labels)

    ip_configuration {
      # Applications reach Cloud SQL over the existing private-services-access
      # peering. No public address or authorized network is ever configured.
      ipv4_enabled    = false
      private_network = var.network_self_link
      ssl_mode        = "ENCRYPTED_ONLY"
    }

    backup_configuration {
      enabled                        = true
      start_time                     = var.backup_start_time
      location                       = var.backup_location
      point_in_time_recovery_enabled = true
      transaction_log_retention_days = var.transaction_log_retention_days

      backup_retention_settings {
        retained_backups = var.retained_backups
        retention_unit   = "COUNT"
      }
    }

    maintenance_window {
      day          = var.maintenance_day
      hour         = var.maintenance_hour
      update_track = var.maintenance_update_track
    }

    insights_config {
      query_insights_enabled  = true
      query_string_length     = 1024
      record_application_tags = true
      record_client_address   = true
      query_plans_per_minute  = 5
    }

    dynamic "database_flags" {
      for_each = local.database_flags

      content {
        name  = database_flags.key
        value = database_flags.value
      }
    }
  }

  timeouts {
    create = "60m"
    update = "60m"
    delete = "60m"
  }

  lifecycle {
    precondition {
      condition     = can(regex("/apps-${var.environment}$", var.network_self_link))
      error_message = "network_self_link must select the apps-${var.environment} VPC for environment ${var.environment}."
    }

    precondition {
      condition = (
        var.disk_autoresize_limit_gb == 0 ||
        var.disk_autoresize_limit_gb >= var.disk_size_gb
      )
      error_message = "disk_autoresize_limit_gb must be zero or at least disk_size_gb."
    }
  }
}

resource "google_sql_database" "this" {
  for_each = var.databases

  project   = var.project_id
  instance  = google_sql_database_instance.this.name
  name      = each.key
  charset   = each.value.charset
  collation = each.value.collation
}

resource "google_sql_user" "iam" {
  for_each = var.iam_users

  project  = var.project_id
  instance = google_sql_database_instance.this.name
  name     = each.key
  type     = each.value
}
