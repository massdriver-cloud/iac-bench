locals {
  # IAM database authentication is a security standard, not a per-instance
  # decision: it is merged in last so it always wins over var.database_flags.
  database_flags = merge(var.database_flags, { "cloudsql.iam_authentication" = "on" })
}

resource "google_sql_database_instance" "this" {
  project          = var.project_id
  name             = var.instance_name
  region           = var.region
  database_version = var.database_version

  # null means Google-managed encryption keys.
  encryption_key_name = var.encryption_key_name

  deletion_protection = var.deletion_protection

  settings {
    tier              = var.tier
    edition           = var.edition
    availability_type = var.availability_type

    disk_size             = var.disk_size_gb
    disk_type             = var.disk_type
    disk_autoresize       = true
    disk_autoresize_limit = var.disk_autoresize_limit_gb

    user_labels = var.labels

    pricing_plan      = "PER_USE"
    activation_policy = "ALWAYS"

    # Private connectivity only. Applications on GKE and Compute Engine reach
    # the instance over the environment VPC; there is no public IP. Private
    # services access on the network is owned and pre-configured by the
    # network team.
    ip_configuration {
      ipv4_enabled       = false
      private_network    = var.network_self_link
      allocated_ip_range = var.allocated_ip_range
      ssl_mode           = var.ssl_mode
    }

    backup_configuration {
      enabled                        = var.backup.enabled
      start_time                     = var.backup.start_time
      point_in_time_recovery_enabled = var.backup.point_in_time_recovery_enabled
      transaction_log_retention_days = var.backup.transaction_log_retention_days

      backup_retention_settings {
        retained_backups = var.backup.retained_backups
        retention_unit   = "COUNT"
      }
    }

    maintenance_window {
      day          = var.maintenance_window.day
      hour         = var.maintenance_window.hour
      update_track = var.maintenance_window.update_track
    }

    # Query Insights is on for every instance: uniform observability is one of
    # the things nobody should have to re-decide.
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
    create = "45m"
    update = "45m"
    delete = "45m"
  }

  lifecycle {
    precondition {
      condition     = var.availability_type == "ZONAL" || var.backup.enabled
      error_message = "Cloud SQL requires backups to be enabled on REGIONAL (highly available) instances."
    }

    precondition {
      condition     = var.backup.enabled || !var.backup.point_in_time_recovery_enabled
      error_message = "backup.point_in_time_recovery_enabled requires backup.enabled = true."
    }

    precondition {
      condition     = !(var.edition == "ENTERPRISE_PLUS" && contains(["db-f1-micro", "db-g1-small"], var.tier))
      error_message = "Shared-core tiers (db-f1-micro, db-g1-small) are only available on the ENTERPRISE edition."
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

# Logins exist only for Google identities. There are deliberately no
# password-based (BUILT_IN) users: database access is audited by Google
# identity, so IAM authentication is the only way in.
resource "google_sql_user" "iam" {
  for_each = var.iam_users

  project  = var.project_id
  instance = google_sql_database_instance.this.name
  # Cloud SQL names IAM service-account logins without the
  # ".gserviceaccount.com" suffix.
  name = each.value.type == "CLOUD_IAM_SERVICE_ACCOUNT" ? trimsuffix(each.value.email, ".gserviceaccount.com") : each.value.email
  type = each.value.type
}
