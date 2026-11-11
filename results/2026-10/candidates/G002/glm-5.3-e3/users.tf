###############################################################################
# IAM database users.
#
# One Cloud SQL login per Google identity - engineer, workload service
# account or group - so every database session is attributable to an identity
# the security team can audit. These logins carry no password: authentication
# happens with the identity's OAuth token (see README). In-database
# privileges (roles, GRANTs) are deliberately not managed here; that needs a
# SQL session and is done with normal DBA tooling after connecting as
# postgres.
###############################################################################

resource "google_sql_user" "iam" {
  for_each = local.iam_users
  project  = var.project_id
  instance = google_sql_database_instance.this.name
  name     = each.key
  type     = each.value.type
}
