locals {
  # Accepts a bare network name ("apps-dev"), a partial path
  # ("projects/<p>/global/networks/<n>") or a full self-link URL, and
  # normalizes to a self-link. Bare names resolve in var.project_id; use a
  # path or URL for a network that lives elsewhere (e.g. a Shared VPC host
  # project).
  network_self_link = (
    startswith(var.network, "https://") ? var.network :
    startswith(var.network, "projects/") ? "https://www.googleapis.com/compute/v1/${var.network}" :
    "https://www.googleapis.com/compute/v1/projects/${var.project_id}/global/networks/${var.network}"
  )

  # IAM database authentication is an organization-wide standard: the flag is
  # always on and cannot be disabled by caller-supplied flags (the module's
  # entry wins the merge).
  database_flags = merge(
    var.database_flags,
    { "cloudsql.iam_authentication" = "on" }
  )
}

resource "google_sql_database_instance" "this" {
  project             = var.project_id
  name                = var.name
  region              = var.region
  database_version    = var.database_version
  deletion_protection = var.deletion_protection
  encryption_key_name = var.encryption_key_name

  settings {
    tier                  = var.tier
    edition               = var.edition
    availability_type     = var.availability_type
    disk_type             = var.disk_type
    disk_size             = var.disk_size_gb
    disk_autoresize       = true
    disk_autoresize_limit = var.disk_autoresize_limit_gb
    pricing_plan          = "PER_USE"
    activation_policy     = "ALWAYS"
    user_labels           = var.labels

    # Private IP only. Applications on GKE and Compute Engine reach the
    # instance from the environment's VPC over private services access, which
    # the network team has already configured. Public IP and authorized
    # networks are deliberately not supported by this module.
    ip_configuration {
      ipv4_enabled    = false
      private_network = local.network_self_link
      ssl_mode        = var.ssl_mode
    }

    backup_configuration {
      enabled                        = var.backup.enabled
      start_time                     = var.backup.start_time
      point_in_time_recovery_enabled = var.backup.point_in_time_recovery
      transaction_log_retention_days = var.backup.transaction_log_retention_days

      backup_retention_settings {
        retained_backups = var.backup.retained_backups
      }
    }

    maintenance_window {
      day          = var.maintenance_window.day
      hour         = var.maintenance_window.hour
      update_track = var.maintenance_window.update_track
    }

    insights_config {
      query_insights_enabled  = var.query_insights.enabled
      query_string_length     = var.query_insights.query_string_length
      record_application_tags = var.query_insights.record_application_tags
      record_client_address   = var.query_insights.record_client_address
      query_plans_per_minute  = var.query_insights.query_plans_per_minute
    }

    dynamic "database_flags" {
      for_each = local.database_flags

      content {
        name  = database_flags.key
        value = database_flags.value
      }
    }
  }

  # Storage autoresize can grow the disk beyond the configured floor; never
  # let OpenTofu try to shrink it back (Cloud SQL cannot shrink disks).
  lifecycle {
    ignore_changes = [settings[0].disk_size]
  }

  timeouts {
    create = "45m"
    update = "45m"
    delete = "30m"
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

# IAM database logins. Password (BUILT_IN) users are deliberately not
# supported: every engineer and every workload authenticates with its Google
# identity, which is what the security team audits.

resource "google_sql_user" "iam_users" {
  for_each = var.iam_users

  project  = var.project_id
  instance = google_sql_database_instance.this.name
  name     = each.value
  type     = "CLOUD_IAM_USER"
}

resource "google_sql_user" "iam_service_accounts" {
  for_each = var.iam_service_accounts

  project  = var.project_id
  instance = google_sql_database_instance.this.name
  # Cloud SQL requires service-account logins without the
  # ".gserviceaccount.com" suffix.
  name = trimsuffix(each.value, ".gserviceaccount.com")
  type = "CLOUD_IAM_SERVICE_ACCOUNT"
}
