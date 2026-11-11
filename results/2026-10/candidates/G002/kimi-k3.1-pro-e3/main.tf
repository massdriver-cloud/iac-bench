locals {
  # These defaults establish a useful operational baseline while leaving normal
  # PostgreSQL tuning under DBA control. IAM authentication is non-negotiable.
  baseline_database_flags = {
    "cloudsql.iam_authentication" = "on"
    "log_checkpoints"             = "on"
    "log_connections"             = "on"
    "log_disconnections"          = "on"
    "log_lock_waits"              = "on"
    "log_temp_files"              = "0"
  }

  database_flags = merge(
    local.baseline_database_flags,
    var.database_flags,
    { "cloudsql.iam_authentication" = "on" }
  )

  labels = merge(var.labels, {
    "component"  = "postgresql"
    "managed-by" = "opentofu"
  })
}

resource "google_sql_database_instance" "this" {
  project             = var.project_id
  name                = var.instance_name
  region              = var.region
  database_version    = var.database_version
  deletion_protection = var.deletion_protection
  encryption_key_name = var.encryption_key_name

  settings {
    tier                        = var.machine_type
    edition                     = var.edition
    availability_type           = var.availability_type
    activation_policy           = "ALWAYS"
    pricing_plan                = "PER_USE"
    disk_type                   = var.disk_type
    disk_size                   = var.disk_size
    disk_autoresize             = true
    disk_autoresize_limit       = var.disk_autoresize_limit
    deletion_protection_enabled = var.deletion_protection
    user_labels                 = local.labels

    # The only connectivity exposed by this module is encrypted private IP.
    # Private services access and its allocated IP range are network-team owned.
    ip_configuration {
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
        retained_backups = var.backup_retained_backups
        retention_unit   = "COUNT"
      }
    }

    maintenance_window {
      day          = var.maintenance_day
      hour         = var.maintenance_hour
      update_track = "stable"
    }

    insights_config {
      query_insights_enabled  = true
      query_string_length     = var.query_string_length
      record_application_tags = true
      record_client_address   = true
      query_plans_per_minute  = var.query_plans_per_minute
    }

    dynamic "database_flags" {
      for_each = local.database_flags
      content {
        name  = database_flags.key
        value = database_flags.value
      }
    }

    dynamic "location_preference" {
      for_each = var.zone == null && var.secondary_zone == null ? [] : [true]
      content {
        zone           = var.zone
        secondary_zone = var.secondary_zone
      }
    }
  }

  lifecycle {
    precondition {
      condition     = var.disk_autoresize_limit == 0 || var.disk_autoresize_limit >= var.disk_size
      error_message = "disk_autoresize_limit must be 0 (unlimited) or at least disk_size."
    }

    precondition {
      condition     = var.secondary_zone == null || var.zone != null
      error_message = "zone must be set when secondary_zone is set."
    }

    precondition {
      condition     = var.availability_type == "REGIONAL" || var.secondary_zone == null
      error_message = "secondary_zone can only be set for a REGIONAL instance."
    }
  }

  timeouts {
    create = "60m"
    update = "60m"
    delete = "30m"
  }
}

resource "google_sql_database" "additional" {
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

  # A password is deliberately never set. These principals authenticate with
  # their existing Google identities, and access is attributable to that identity.
  depends_on = [google_sql_database_instance.this]
}
