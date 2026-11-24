resource "google_sql_user" "iam_users" {
  for_each = local.iam_principals

  name            = each.value.sql_name
  instance        = google_sql_database_instance.primary.name
  type            = each.value.sql_type
  deletion_policy = var.iam_user_deletion_policy
}

resource "google_project_iam_member" "cloudsql_instance_user" {
  for_each = local.iam_principals

  project = data.google_project.current.project_id
  role    = "roles/cloudsql.instanceUser"
  member  = each.value.member

  condition {
    title       = "cloudsql-instance-user-${local.instance_name}"
    description = "Allow IAM database login only for Cloud SQL instance ${local.instance_name} and its read replicas."
    expression  = local.iam_condition_expression
  }

  depends_on = [google_sql_database_instance.primary]
}

resource "google_project_iam_member" "cloudsql_client" {
  for_each = local.iam_principals

  project = data.google_project.current.project_id
  role    = "roles/cloudsql.client"
  member  = each.value.member

  condition {
    title       = "cloudsql-client-${local.instance_name}"
    description = "Allow Cloud SQL Auth Proxy and Connector access only for instance ${local.instance_name} and its read replicas."
    expression  = local.iam_condition_expression
  }

  depends_on = [google_sql_database_instance.primary]
}
