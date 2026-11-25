resource "google_sql_user" "iam" {
  for_each = local.iam_principals

  name     = local.iam_user_names[each.key]
  project  = var.project_id
  instance = google_sql_database_instance.this.name
  type     = each.value.type == "service_account" ? "CLOUD_IAM_SERVICE_ACCOUNT" : "CLOUD_IAM_USER"
}
