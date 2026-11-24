# -----------------------------------------------------------------------------
# Cloud SQL IAM Database Users
# -----------------------------------------------------------------------------

resource "google_sql_user" "iam_users" {
  for_each = var.iam_users

  name            = each.value
  instance        = google_sql_database_instance.primary.name
  type            = "CLOUD_IAM_USER"
  deletion_policy = "ABANDON"
}

resource "google_sql_user" "iam_service_accounts" {
  for_each = local.iam_service_accounts

  name            = each.value.sql_user_id
  instance        = google_sql_database_instance.primary.name
  type            = "CLOUD_IAM_SERVICE_ACCOUNT"
  deletion_policy = "ABANDON"
}

resource "google_sql_user" "iam_groups" {
  for_each = var.iam_groups

  name            = each.value
  instance        = google_sql_database_instance.primary.name
  type            = "CLOUD_IAM_GROUP"
  deletion_policy = "ABANDON"
}

# -----------------------------------------------------------------------------
# Instance-Scoped GCP IAM Roles for Cloud SQL Authentication & Connectivity
# -----------------------------------------------------------------------------

locals {
  iam_members = concat(
    [for u in sort(tolist(var.iam_users)) : "user:${u}"],
    [for sa in sort(keys(local.iam_service_accounts)) : "serviceAccount:${local.iam_service_accounts[sa].full_email}"],
    [for g in sort(tolist(var.iam_groups)) : "group:${g}"]
  )

  iam_role_bindings = var.grant_project_iam_roles ? {
    for pair in flatten([
      for member in local.iam_members : [
        for role in ["roles/cloudsql.instanceUser", "roles/cloudsql.client"] : {
          key    = "${role}/${member}"
          role   = role
          member = member
        }
      ]
    ]) : pair.key => pair
  } : {}
}

resource "google_project_iam_member" "cloudsql_access" {
  for_each = local.iam_role_bindings

  project = local.project_id
  role    = each.value.role
  member  = each.value.member

  condition {
    title       = "cloudsql-${local.instance_name}"
    description = "Restrict Cloud SQL access to ${local.instance_name} and its read replicas."
    expression  = local.iam_instance_condition_expression
  }
}
