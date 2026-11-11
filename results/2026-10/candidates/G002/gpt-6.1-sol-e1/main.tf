locals {
  network = "projects/${var.network_project_id}/global/networks/apps-${var.environment}"
  flags   = merge(var.database_flags, { "cloudsql.iam_authentication" = "on" })
  identities = merge(
    { for email in var.iam_users : "user:${email}" => { name = email, type = "CLOUD_IAM_USER" } },
    { for email in var.iam_service_accounts : "serviceAccount:${email}" => { name = trimsuffix(email, ".gserviceaccount.com"), type = "CLOUD_IAM_SERVICE_ACCOUNT" } },
    { for email in var.iam_groups : "group:${email}" => { name = email, type = "CLOUD_IAM_GROUP" } }
  )
  access_roles = toset(["roles/cloudsql.client", "roles/cloudsql.instanceUser"])
  iam_bindings = {
    for pair in setproduct(keys(local.identities), local.access_roles) : "${pair[0]}|${pair[1]}" => {
      member = pair[0]
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

  # All access must use a Cloud SQL Auth Proxy or language connector, over private IP.
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
    user_labels = merge(var.labels, {
      environment = var.environment
      managed_by  = "opentofu"
    })

    ip_configuration {
      ipv4_enabled                                  = false
      private_network                               = local.network
      enable_private_path_for_google_cloud_services = false
      ssl_mode                                      = "ENCRYPTED_ONLY"
    }

    backup_configuration {
      enabled                        = true
      start_time                     = var.backup_start_time
      point_in_time_recovery_enabled = true
      transaction_log_retention_days = 7
      backup_retention_settings {
        retained_backups = var.backup_retention_count
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

  lifecycle {
    # Cloud SQL increases storage automatically; do not attempt to shrink it afterwards.
    ignore_changes = [settings[0].disk_size]
    precondition {
      condition     = var.environment != "prod" || var.availability_type == "REGIONAL"
      error_message = "Production instances must use REGIONAL high availability."
    }
  }
}

resource "google_sql_database" "this" {
  for_each  = var.databases
  project   = var.project_id
  instance  = google_sql_database_instance.this.name
  name      = each.key
  charset   = each.value.charset
  collation = each.value.collation
}

# Additive, instance-scoped conditional memberships. Do not replace project IAM policies
# or grant access to every other database instance in the project.
resource "google_project_iam_member" "database_access" {
  for_each = local.iam_bindings
  project  = var.project_id
  role     = each.value.role
  member   = each.value.member

  condition {
    title       = "cloudsql-${var.name}"
    description = "Access only the ${var.name} Cloud SQL instance"
    expression  = "resource.name == 'projects/${var.project_id}/instances/${var.name}'"
  }
}

resource "google_sql_user" "iam" {
  for_each = local.identities
  project  = var.project_id
  instance = google_sql_database_instance.this.name
  name     = each.value.name
  type     = each.value.type

  depends_on = [google_project_iam_member.database_access]
}
