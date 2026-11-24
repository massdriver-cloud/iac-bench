# =========================================================================
# IAM database users
# =========================================================================
# Users are Google identities, registered on the instance. They
# authenticate with an IAM-generated login token (the Cloud SQL connectors
# do this for the application; `gcloud sql generate-login-token` for a
# human), so no password ever exists. The security team can therefore
# account for every identity that can reach a database.
#
# These resources only register the identity with the instance. Granting
# roles/cloudsql.instanceUser on the project (or instance) is deliberately
# not done here: that is an IAM change owned by the security team.

resource "google_sql_user" "this" {
  for_each = var.iam_users

  project  = var.project
  instance = google_sql_database_instance.this.name
  name     = each.key
  type     = each.value.type
}
