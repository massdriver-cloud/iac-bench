# -----------------------------------------------------------------------------
# Database access - Google identities only
#
# There is no password authentication anywhere in this module. Every login is
# a Google identity:
#
#   * engineers        -> CLOUD_IAM_USER
#   * teams            -> CLOUD_IAM_GROUP (members log in with their own
#                         identity, the group carries the grant)
#   * GKE / GCE
#     workloads        -> CLOUD_IAM_SERVICE_ACCOUNT
#
# Two project-level roles are needed next to the SQL login, and the module
# grants both to every principal listed:
#
#   * roles/cloudsql.instanceUser - the cloudsql.instances.login permission
#     that IAM database authentication checks
#   * roles/cloudsql.client - lets the Cloud SQL Auth Proxy / language
#     connectors discover the instance, which is how GKE workloads connect
#
# The module never sets a password for the built-in postgres user, so no
# password login exists unless someone creates one out-of-band.
# -----------------------------------------------------------------------------

resource "google_sql_user" "iam_database_users" {
  for_each = toset(var.iam_database_users)

  name     = each.value
  instance = google_sql_database_instance.primary.name
  type     = "CLOUD_IAM_USER"
}

resource "google_sql_user" "iam_database_groups" {
  for_each = toset(var.iam_database_groups)

  name     = each.value
  instance = google_sql_database_instance.primary.name
  type     = "CLOUD_IAM_GROUP"
}

resource "google_sql_user" "iam_service_accounts" {
  for_each = toset(var.iam_service_accounts)

  name     = each.value
  instance = google_sql_database_instance.primary.name
  type     = "CLOUD_IAM_SERVICE_ACCOUNT"
}

resource "google_project_iam_member" "cloudsql_instance_user" {
  for_each = local.iam_principals

  project = var.project
  role    = "roles/cloudsql.instanceUser"
  member  = format("%s:%s", each.value, each.key)
}

resource "google_project_iam_member" "cloudsql_client" {
  for_each = local.iam_principals

  project = var.project
  role    = "roles/cloudsql.client"
  member  = format("%s:%s", each.value, each.key)
}
