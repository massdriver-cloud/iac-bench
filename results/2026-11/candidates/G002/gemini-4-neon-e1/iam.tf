################################################################################
# Cloud SQL IAM Database Principals
# Every engineer and workload authenticates via their Google identity; built-in
# password users are intentionally not managed by this module.
################################################################################

resource "google_sql_user" "iam_users" {
  for_each = var.iam_users

  instance = google_sql_database_instance.primary.name
  name     = each.value
  type     = "CLOUD_IAM_USER"
}

resource "google_sql_user" "iam_service_accounts" {
  for_each = local.iam_service_account_usernames

  instance = google_sql_database_instance.primary.name
  name     = each.value
  type     = "CLOUD_IAM_SERVICE_ACCOUNT"
}

resource "google_sql_user" "iam_groups" {
  for_each = var.iam_groups

  instance = google_sql_database_instance.primary.name
  name     = each.value
  type     = "CLOUD_IAM_GROUP"
}

################################################################################
# Scoped GCP IAM Bindings for Cloud SQL IAM Authentication & Connectivity
################################################################################

resource "google_project_iam_member" "cloudsql_access" {
  for_each = local.iam_bindings

  project = data.google_client_config.current.project
  role    = each.value.role
  member  = each.value.member

  condition {
    title       = "cloudsql-${local.instance_name}"
    description = "Restrict Cloud SQL access to instance ${local.instance_name} and its read replicas."
    expression  = local.iam_condition_expression
  }

  depends_on = [
    google_sql_database_instance.primary,
    google_sql_database_instance.read_replica,
  ]
}
