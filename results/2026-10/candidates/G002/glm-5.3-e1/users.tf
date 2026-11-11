###############################################################################
# Who can log in: Google identities only
###############################################################################

# Every engineer and every workload already has a Google identity, and the
# security team audits database access by those identities - so IAM database
# authentication is the only way in. This module creates no password users and
# stores no secrets; the built-in postgres user is left without a password, so
# it cannot be logged into at all until a DBA deliberately sets one.
#
# Two things must exist for an identity to log in with IAM database
# authentication, and this module creates both:
#
#   1. an IAM database user record on the instance (google_sql_user). This is
#      the per-instance gate: no record, no login, regardless of anything else.
#
#   2. the cloudsql.instances.login permission, carried by
#      roles/cloudsql.instanceUser. The google provider has no per-instance
#      IAM resource for Cloud SQL, so the role is granted in the instance's
#      project. It carries no admin or connect rights of its own - it only
#      enables IAM logins, and the user record from (1) decides where.
#
# Everything beyond login - roles, GRANTs, default privileges - is real
# PostgreSQL work. Cloud SQL has no API for it, so it stays with the DBAs and
# their migration tooling rather than being faked in Terraform.

resource "google_sql_user" "iam_user" {
  for_each = var.iam_users
  name     = each.value
  instance = google_sql_database_instance.instance.name
  type     = "CLOUD_IAM_USER"
}

resource "google_sql_user" "iam_service_account" {
  for_each = var.iam_service_accounts
  name     = each.value
  instance = google_sql_database_instance.instance.name
  type     = "CLOUD_IAM_SERVICE_ACCOUNT"
}

resource "google_project_iam_member" "iam_user_login" {
  for_each = var.iam_users
  project  = var.project_id
  role     = "roles/cloudsql.instanceUser"
  member   = "user:${each.value}"
}

resource "google_project_iam_member" "iam_service_account_login" {
  for_each = var.iam_service_accounts
  project  = var.project_id
  role     = "roles/cloudsql.instanceUser"
  member   = "serviceAccount:${each.value}"
}
