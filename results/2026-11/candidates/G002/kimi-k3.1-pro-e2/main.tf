locals {
  # These flags make identity and connection auditing consistent. Callers may tune
  # the logging flags, but the final merge makes IAM authentication non-optional.
  standard_database_flags = {
    "cloudsql.iam_authentication" = "on"
    "log_connections"             = "on"
    "log_disconnections"          = "on"
    "log_lock_waits"              = "on"
    "log_statement"               = "ddl"
  }

  database_flags = merge(
    local.standard_database_flags,
    var.database_flags,
    { "cloudsql.iam_authentication" = "on" }
  )

  labels = merge(var.labels, { managed_by = "opentofu" })

  iam_principals = {
    for email, user_type in var.iam_users : email => {
      user_type = user_type
      member    = user_type == "CLOUD_IAM_USER" ? "user:${email}" : "serviceAccount:${email}"
    }
  }
}

resource "google_sql_database_instance" "this" {
  project             = var.project_id
  name                = var.instance_name
  region              = var.region
  database_version    = var.database_version
  deletion_protection = var.deletion_protection

  settings {
    tier                        = var.tier
    edition                     = var.edition
    availability_type           = var.availability_type
    activation_policy           = "ALWAYS"
    pricing_plan                = "PER_USE"
    disk_type                   = var.disk_type
    disk_size                   = var.disk_size
    disk_autoresize             = var.disk_autoresize
    disk_autoresize_limit       = var.disk_autoresize_limit
    deletion_protection_enabled = var.deletion_protection
    user_labels                 = local.labels

    ip_configuration {
      # Workloads connect only through the network team's existing private
      # services access. There is deliberately no public-IP or authorized-network
      # escape hatch. TLS remains mandatory even on the private VPC path.
      ipv4_enabled    = false
      private_network = var.network_self_link
      ssl_mode        = "ENCRYPTED_ONLY"
    }

    backup_configuration {
      enabled                        = true
      point_in_time_recovery_enabled = true
      start_time                     = var.backup.start_time
      location                       = var.backup.location
      transaction_log_retention_days = var.backup.transaction_log_retention_days

      backup_retention_settings {
        retained_backups = var.backup.retained_backups
        retention_unit   = "COUNT"
      }
    }

    maintenance_window {
      day          = var.maintenance_window.day
      hour         = var.maintenance_window.hour
      update_track = "stable"
    }

    insights_config {
      query_insights_enabled  = true
      query_string_length     = 1024
      query_plans_per_minute  = 5
      record_application_tags = true
      record_client_address   = true
    }

    dynamic "location_preference" {
      for_each = var.zone == null ? [] : [var.zone]
      content {
        zone = location_preference.value
      }
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
}

resource "google_sql_database" "this" {
  for_each = var.databases

  project         = var.project_id
  instance        = google_sql_database_instance.this.name
  name            = each.key
  charset         = each.value.charset
  collation       = each.value.collation
  deletion_policy = each.value.deletion_policy
}

resource "google_sql_user" "iam" {
  for_each = local.iam_principals

  project  = var.project_id
  instance = google_sql_database_instance.this.name
  name     = each.key
  type     = each.value.user_type
}

# IAM authentication has two halves: the SQL user above and permission to log in.
# Cloud SQL's login and connector roles are granted at project level. These are
# non-authoritative member resources, so unrelated IAM grants are left untouched.
resource "google_project_iam_member" "instance_user" {
  for_each = local.iam_principals

  project = var.project_id
  role    = "roles/cloudsql.instanceUser"
  member  = each.value.member
}

resource "google_project_iam_member" "client" {
  for_each = local.iam_principals

  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = each.value.member
}
