locals {
  # Automatically enforce cloudsql.iam_authentication = "on" while preserving user flags
  user_flags_filtered = [
    for flag in var.database_flags : flag
    if flag.name != "cloudsql.iam_authentication"
  ]

  default_flags = [
    {
      name  = "cloudsql.iam_authentication"
      value = "on"
    }
  ]

  all_database_flags = concat(local.default_flags, local.user_flags_filtered)

  # Process IAM users and service accounts
  formatted_iam_users = [
    for item in var.iam_users : {
      raw_email = item.email
      clean_email = replace(
        replace(item.email, "user:", ""),
        "serviceAccount:",
        ""
      )
      specified_type = item.type
    }
  ]

  processed_iam_users = [
    for u in local.formatted_iam_users : {
      is_sa = (
        u.specified_type == "CLOUD_IAM_SERVICE_ACCOUNT" ||
        (u.specified_type == null && (
          endswith(u.clean_email, ".gserviceaccount.com") ||
          contains(split("@", u.clean_email), "gserviceaccount.com") ||
          endswith(u.clean_email, ".iam")
        ))
      )
      clean_email = u.clean_email
    }
  ]

  iam_users_map = {
    for u in local.processed_iam_users :
    u.clean_email => {
      type         = u.is_sa ? "CLOUD_IAM_SERVICE_ACCOUNT" : "CLOUD_IAM_USER"
      db_user_name = u.is_sa ? trimsuffix(u.clean_email, ".gserviceaccount.com") : u.clean_email
      iam_member   = u.is_sa ? (
        endswith(u.clean_email, ".gserviceaccount.com") ? "serviceAccount:${u.clean_email}" : "serviceAccount:${u.clean_email}.gserviceaccount.com"
      ) : "user:${u.clean_email}"
    }
  }

  iam_role_grants = var.grant_iam_roles ? flatten([
    for email, u in local.iam_users_map : [
      {
        key    = "${u.iam_member}-roles/cloudsql.client"
        member = u.iam_member
        role   = "roles/cloudsql.client"
      },
      {
        key    = "${u.iam_member}-roles/cloudsql.instanceUser"
        member = u.iam_member
        role   = "roles/cloudsql.instanceUser"
      }
    ]
  ]) : []
}

resource "google_sql_database_instance" "main" {
  name                 = var.name
  project              = var.project_id
  region               = var.region
  database_version     = var.database_version
  master_instance_name = var.master_instance_name
  encryption_key_name  = var.encryption_key_name
  deletion_protection  = var.deletion_protection

  settings {
    tier                  = var.tier
    activation_policy     = "ALWAYS"
    availability_type     = var.availability_type
    disk_type             = var.disk_type
    disk_size             = var.disk_size
    disk_autoresize       = true
    disk_autoresize_limit = var.disk_autoresize_limit
    user_labels           = var.user_labels

    ip_configuration {
      ipv4_enabled                                  = var.ipv4_enabled
      private_network                               = var.private_network
      enable_private_path_for_google_cloud_services = true
      ssl_mode                                      = var.ssl_mode
    }

    backup_configuration {
      enabled                        = true
      start_time                     = var.backup_start_time
      point_in_time_recovery_enabled = true
      transaction_log_retention_days = var.backup_transaction_log_retention_days
      backup_retention_settings {
        retained_backups = var.backup_retention_days
        retention_unit   = "COUNT"
      }
    }

    maintenance_window {
      day          = var.maintenance_window_day
      hour         = var.maintenance_window_hour
      update_track = var.maintenance_window_update_track
    }

    insights_config {
      query_insights_enabled  = var.query_insights_enabled
      record_application_tags = var.query_insights_record_application_tags
      record_client_address   = var.query_insights_record_client_address
      query_plans_per_minute  = var.query_insights_query_plans_per_minute
      query_string_length     = var.query_insights_query_string_length
    }

    dynamic "database_flags" {
      for_each = local.all_database_flags
      content {
        name  = database_flags.value.name
        value = database_flags.value.value
      }
    }

    dynamic "location_preference" {
      for_each = var.zone != null && var.zone != "" ? [var.zone] : []
      content {
        zone = location_preference.value
      }
    }
  }
}

resource "google_sql_database" "databases" {
  for_each = {
    for db in var.databases : db.name => db
  }

  name      = each.value.name
  instance  = google_sql_database_instance.main.name
  charset   = each.value.charset
  collation = each.value.collation
  project   = var.project_id
}

resource "google_sql_user" "builtin_users" {
  for_each = {
    for u in var.users : u.name => u
  }

  name     = each.value.name
  instance = google_sql_database_instance.main.name
  password = each.value.password
  project  = var.project_id
}

resource "google_sql_user" "iam_users" {
  for_each = local.iam_users_map

  name     = each.value.db_user_name
  instance = google_sql_database_instance.main.name
  type     = each.value.type
  project  = var.project_id
}

resource "google_project_iam_member" "iam_roles" {
  for_each = {
    for grant in local.iam_role_grants : grant.key => grant
  }

  project = var.project_id != null ? var.project_id : google_sql_database_instance.main.project
  role    = each.value.role
  member  = each.value.member
}
