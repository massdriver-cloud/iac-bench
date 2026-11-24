resource "google_sql_user" "iam" {
  for_each = local.iam_identities

  name     = each.value.sql_username
  instance = google_sql_database_instance.primary.name
  type     = each.value.sql_type
}

resource "google_project_iam_member" "cloudsql_access" {
  for_each = local.iam_role_bindings

  project = local.project_id
  role    = each.value.role
  member  = each.value.member

  condition {
    title       = "cloudsql-${google_sql_database_instance.primary.name}"
    description = "Least-privilege Cloud SQL IAM access scoped to ${google_sql_database_instance.primary.name} and its read replicas."
    expression = format(
      "resource.type == \"sqladmin.googleapis.com/Instance\" && (%s)",
      join(" || ", [
        for inst_name in concat(
          [google_sql_database_instance.primary.name],
          [for k in sort(keys(google_sql_database_instance.read_replica)) : google_sql_database_instance.read_replica[k].name]
        ) :
        "resource.name == \"projects/${local.project_id}/instances/${inst_name}\""
      ])
    )
  }
}
