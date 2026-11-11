###############################################################################
# IAM database authentication
#
# The access model: every engineer and every workload already has a Google
# identity, and the security team audits database access by those identities,
# so PostgreSQL logins are IAM principals. No passwords are involved.
###############################################################################

locals {
  iam_flags = {
    for email, opts in var.iam_users :
    email => {
      service_account = endswith(lower(email), ".gserviceaccount.com")
      grant_client    = opts.grant_cloudsql_client
    }
  }

  # Cloud SQL expects the full email as the login name for user principals,
  # but the email without the .gserviceaccount.com suffix for service
  # accounts.
  iam_principals = {
    for email, flags in local.iam_flags :
    email => {
      member       = flags.service_account ? "serviceAccount:${email}" : "user:${email}"
      login_name   = flags.service_account ? trimsuffix(lower(email), ".gserviceaccount.com") : lower(email)
      user_type    = flags.service_account ? "IAM_SERVICE_ACCOUNT" : "IAM_USER"
      grant_client = flags.grant_client
    }
  }
}

resource "google_sql_user" "iam" {
  for_each = local.iam_principals

  project  = var.project_id
  instance = google_sql_database_instance.primary.name
  name     = each.value.login_name
  type     = each.value.user_type
}

# Required to log in with IAM database authentication.
resource "google_project_iam_member" "instance_user" {
  for_each = local.iam_principals

  project = var.project_id
  role    = "roles/cloudsql.instanceUser"
  member  = each.value.member
}

# Required by the Cloud SQL Auth Proxy and the Cloud SQL language connectors.
# Opt-in, because it is project-scoped: it allows connecting to every Cloud
# SQL instance in the project.
resource "google_project_iam_member" "client" {
  for_each = { for email, p in local.iam_principals : email => p if p.grant_client }

  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = each.value.member
}

###############################################################################
# Break-glass password logins (optional, empty by default)
###############################################################################

# The variable is marked sensitive because of the password values; the map
# keys (usernames) are the resource instance keys, so they are lifted out of
# the sensitive value explicitly and the passwords are read back through the
# variable to keep them sensitive.
resource "google_sql_user" "builtin" {
  for_each = toset(nonsensitive(keys(var.builtin_users)))

  project  = var.project_id
  instance = google_sql_database_instance.primary.name
  name     = each.key
  password = var.builtin_users[each.key]
  type     = "BUILT_IN"
}
