# Database access is by Google identity only. The module creates no password
# users; the built-in `postgres` user exists but has no password and so cannot
# log in.
#
# Each principal gets:
#   - a Cloud SQL IAM database user, so PostgreSQL knows the identity, and
#   - the two IAM roles needed to reach this instance, scoped to this instance
#     alone with an IAM condition:
#       roles/cloudsql.instanceUser  log in with IAM database authentication
#       roles/cloudsql.client        connect through the Cloud SQL Auth Proxy
#                                    and language connectors
#
# What a principal may do inside PostgreSQL (GRANTs, role membership) stays
# with the DBAs; a new IAM database user starts with no privileges.

locals {
  iam_principals = merge(
    {
      for email in var.iam_groups : email => {
        member   = "group:${email}"
        db_user  = email
        sql_type = "CLOUD_IAM_GROUP"
      }
    },
    {
      for email in var.iam_users : email => {
        member   = "user:${email}"
        db_user  = email
        sql_type = "CLOUD_IAM_USER"
      }
    },
    {
      for email in var.iam_service_accounts : email => {
        member = "serviceAccount:${email}"
        # Cloud SQL names service account users without the domain suffix.
        db_user  = trimsuffix(email, ".gserviceaccount.com")
        sql_type = "CLOUD_IAM_SERVICE_ACCOUNT"
      }
    },
  )

  iam_roles = ["roles/cloudsql.instanceUser", "roles/cloudsql.client"]

  iam_grants = merge([
    for email, principal in local.iam_principals : {
      for role in local.iam_roles : "${email}/${role}" => {
        member = principal.member
        role   = role
      }
    }
  ]...)
}

resource "google_sql_user" "iam" {
  for_each = local.iam_principals

  project  = var.project_id
  instance = google_sql_database_instance.this.name
  name     = each.value.db_user
  type     = each.value.sql_type
}

resource "google_project_iam_member" "instance_access" {
  for_each = local.iam_grants

  project = var.project_id
  role    = each.value.role
  member  = each.value.member

  condition {
    title       = "only-${local.instance_name}"
    description = "Limits the role to the ${local.instance_name} Cloud SQL instance."
    expression  = "resource.service == \"sqladmin.googleapis.com\" && resource.name == \"projects/${var.project_id}/instances/${local.instance_name}\""
  }
}
