locals {
  # Platform-standard PostgreSQL flags. DBAs may override the tunable ones
  # through var.database_flags.
  default_flags = {
    "log_checkpoints"            = "on"
    "log_lock_waits"             = "on"
    "log_temp_files"             = "0"
    "log_min_duration_statement" = "1000"
    "pgaudit.log"                = "ddl,role,write"
    "timezone"                   = "UTC"
  }

  # Flags the platform always sets. Overriding them is rejected by a
  # precondition, so audit and access controls cannot be turned off per instance.
  locked_flags = {
    "cloudsql.iam_authentication" = "on"
    "cloudsql.enable_pgaudit"     = "on"
    "log_connections"             = "on"
    "log_disconnections"          = "on"
  }

  database_flags = merge(local.default_flags, var.database_flags, local.locked_flags)

  is_prod = var.environment == "prod"

  # Cloud SQL IAM database users drop the .gserviceaccount.com suffix for service accounts.
  iam_user_names = {
    for email, u in var.iam_users : email => u.type == "CLOUD_IAM_SERVICE_ACCOUNT" ? replace(email, ".gserviceaccount.com", "") : email
  }
}

resource "google_sql_database_instance" "this" {
  name                = var.instance_name
  project             = var.project_id
  region              = var.region
  database_version    = var.database_version
  deletion_protection = var.deletion_protection
  encryption_key_name = var.encryption_key_name

  lifecycle {
    precondition {
      condition     = length(setintersection(keys(var.database_flags), keys(local.locked_flags))) == 0
      error_message = "database_flags may not override platform-locked flags: ${join(", ", keys(local.locked_flags))}."
    }

    precondition {
      condition     = can(regex("/networks/apps-${var.environment}$", var.network_self_link))
      error_message = "network_self_link must point to the apps-${var.environment} VPC for environment ${var.environment}."
    }

    precondition {
      condition     = !local.is_prod || var.availability_type == "REGIONAL"
      error_message = "Prod instances must use availability_type REGIONAL."
    }

    precondition {
      condition     = !local.is_prod || var.deletion_protection
      error_message = "Prod instances must have deletion_protection enabled."
    }

    precondition {
      condition     = !local.is_prod || var.retained_backups >= 30
      error_message = "Prod instances must retain at least 30 automated backups."
    }
  }

  settings {
    tier    = var.tier
    edition = var.edition

    availability_type = var.availability_type
    activation_policy = "ALWAYS"
    user_labels       = merge({ environment = var.environment, managed-by = "opentofu" }, var.labels)

    disk_type             = "PD_SSD"
    disk_size             = var.disk_size_gb
    disk_autoresize       = true
    disk_autoresize_limit = var.disk_autoresize_limit_gb

    # Private IP only. Connections must use TLS. Public IP is never enabled.
    ip_configuration {
      ipv4_enabled                                  = false
      private_network                               = var.network_self_link
      ssl_mode                                      = "ENCRYPTED_ONLY"
      enable_private_path_for_google_cloud_services = true
    }

    backup_configuration {
      enabled                        = true
      start_time                     = var.backup_start_time
      point_in_time_recovery_enabled = true
      transaction_log_retention_days = 7

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
    }

    dynamic "database_flags" {
      for_each = local.database_flags
      content {
        name  = database_flags.key
        value = database_flags.value
      }
    }
  }
}

resource "google_sql_database" "this" {
  for_each = var.databases

  name      = each.key
  project   = var.project_id
  instance  = google_sql_database_instance.this.name
  charset   = each.value.charset
  collation = each.value.collation
}

# Database logins are Google identities only (Cloud SQL IAM authentication).
# No passwords are generated or stored in state.
resource "google_sql_user" "iam" {
  for_each = var.iam_users

  name     = local.iam_user_names[each.key]
  project  = var.project_id
  instance = google_sql_database_instance.this.name
  type     = each.value.type
}
