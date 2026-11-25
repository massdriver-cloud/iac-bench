# Authentication is Google-identity-only. The module never provisions a
# password-based (BUILT_IN) database user: every login — engineer or
# workload — maps to a Google identity, which is what the security team
# audits. Authorisation inside PostgreSQL (GRANT statements) belongs to the
# DBA team's SQL migration pipeline; this module owns authentication and
# instance access, not in-database privileges.

resource "google_sql_user" "iam_user" {
  for_each = var.iam_users

  project  = var.project
  instance = google_sql_database_instance.primary.name
  name     = each.value
  type     = "CLOUD_IAM_USER"
}

resource "google_sql_user" "iam_service_account" {
  for_each = var.iam_service_accounts

  project  = var.project
  instance = google_sql_database_instance.primary.name
  name     = each.value
  type     = "CLOUD_IAM_SERVICE_ACCOUNT"
}

# The IAM half of IAM database authentication: every principal with a
# database login needs the cloudsql.instances.login permission
# (roles/cloudsql.instanceUser), and the Cloud SQL connectors / auth proxy
# that GKE and Compute Engine workloads use need cloudsql.instances.get /
# .connect (roles/cloudsql.client) to discover the instance. Non-authoritative
# member bindings, so they coexist with anything a central IAM team manages.
#
# google_project_iam_member requires an explicit project; it is taken from
# the instance resource, which is either var.project or the provider's
# project — the same project the networks live in.
resource "google_project_iam_member" "db_access" {
  for_each = local.iam_grants

  project = google_sql_database_instance.primary.project
  role    = each.value.role
  member  = each.value.member
}
