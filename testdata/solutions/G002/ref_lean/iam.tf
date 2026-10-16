locals {
  login_members = concat(
    [for u in var.iam_users : "user:${u}"],
    [for sa in var.iam_service_accounts : "serviceAccount:${sa}"],
  )
  login_grants = {
    for pair in setproduct(local.login_members, ["roles/cloudsql.instanceUser", "roles/cloudsql.client"]) :
    "${pair[1]} ${pair[0]}" => { member = pair[0], role = pair[1] }
  }
}

# People log in as CLOUD_IAM_USER, workloads as CLOUD_IAM_SERVICE_ACCOUNT
# (Cloud SQL names a service-account user by its email without the
# .gserviceaccount.com suffix).
resource "google_sql_user" "iam" {
  for_each = var.iam_users

  name     = each.value
  instance = google_sql_database_instance.this.name
  type     = "CLOUD_IAM_USER"
}

resource "google_sql_user" "iam_service_account" {
  for_each = var.iam_service_accounts

  name     = trimsuffix(each.value, ".gserviceaccount.com")
  instance = google_sql_database_instance.this.name
  type     = "CLOUD_IAM_SERVICE_ACCOUNT"
}

# A database user alone cannot log in: IAM login needs instanceUser, and the
# Cloud SQL connectors need client. Both are scoped to this instance.
resource "google_project_iam_member" "sql_login" {
  for_each = local.login_grants

  project = google_sql_database_instance.this.project
  role    = each.value.role
  member  = each.value.member

  condition {
    title      = "cloudsql-${google_sql_database_instance.this.name}"
    expression = "resource.name == 'projects/${google_sql_database_instance.this.project}/instances/${google_sql_database_instance.this.name}'"
  }
}
