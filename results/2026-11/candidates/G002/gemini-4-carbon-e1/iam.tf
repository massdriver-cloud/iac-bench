resource "google_sql_user" "iam_user" {
  for_each = var.iam_users

  name            = each.value
  project         = local.project_id
  instance        = google_sql_database_instance.primary.name
  type            = "CLOUD_IAM_USER"
  deletion_policy = var.sql_user_deletion_policy

  lifecycle {
    precondition {
      condition     = length(setintersection(var.iam_users, var.iam_groups)) == 0
      error_message = "An email address cannot appear in both iam_users and iam_groups."
    }
  }
}

resource "google_sql_user" "iam_service_account" {
  for_each = local.service_account_sql_users

  name            = each.value
  project         = local.project_id
  instance        = google_sql_database_instance.primary.name
  type            = "CLOUD_IAM_SERVICE_ACCOUNT"
  deletion_policy = var.sql_user_deletion_policy
}

resource "google_sql_user" "iam_group" {
  for_each = var.iam_groups

  name            = each.value
  project         = local.project_id
  instance        = google_sql_database_instance.primary.name
  type            = "CLOUD_IAM_GROUP"
  deletion_policy = var.sql_user_deletion_policy
}

resource "google_project_iam_member" "cloudsql_client" {
  for_each = var.manage_iam_bindings ? local.iam_members : toset([])

  project = local.project_id
  role    = "roles/cloudsql.client"
  member  = each.value

  condition {
    title       = "cloudsql_client_${local.instance_name}"
    description = "Allow Cloud SQL connectivity only to ${local.instance_name} and its read replicas"
    expression  = "resource.type == \"sqladmin.googleapis.com/Instance\" && (resource.name == \"projects/${local.project_id}/instances/${local.instance_name}\" || resource.name.startsWith(\"projects/${local.project_id}/instances/${local.instance_name}-replica-\"))"
  }
}

resource "google_project_iam_member" "cloudsql_instance_user" {
  for_each = var.manage_iam_bindings ? local.iam_members : toset([])

  project = local.project_id
  role    = "roles/cloudsql.instanceUser"
  member  = each.value

  condition {
    title       = "cloudsql_login_${local.instance_name}"
    description = "Allow Cloud SQL IAM database login only to ${local.instance_name} and its read replicas"
    expression  = "resource.type == \"sqladmin.googleapis.com/Instance\" && (resource.name == \"projects/${local.project_id}/instances/${local.instance_name}\" || resource.name.startsWith(\"projects/${local.project_id}/instances/${local.instance_name}-replica-\"))"
  }
}
