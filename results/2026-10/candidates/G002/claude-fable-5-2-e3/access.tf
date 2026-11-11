###############################################################################
# Access by Google identity
#
# For every principal in var.iam_members the module creates:
#   1. a PostgreSQL role mapped to the identity (IAM database authentication),
#   2. roles/cloudsql.instanceUser - permission to log in as that identity,
#   3. roles/cloudsql.client       - permission to connect (Auth Proxy,
#                                    language connectors),
# with 2 and 3 conditioned on this instance and its replicas, so access to one
# database does not imply access to every database in the project.
#
# No password users are created and no credential is stored in state.
###############################################################################

locals {
  iam_user_types = {
    user           = "CLOUD_IAM_USER"
    serviceAccount = "CLOUD_IAM_SERVICE_ACCOUNT"
    group          = "CLOUD_IAM_GROUP"
  }

  # IAM principal => PostgreSQL role. For service accounts Cloud SQL uses the
  # email without the .gserviceaccount.com suffix as the role name.
  iam_database_users = {
    for m in var.iam_members : m => {
      type = local.iam_user_types[split(":", m)[0]]
      name = trimsuffix(split(":", m)[1], ".gserviceaccount.com")
    }
  }

  iam_roles = ["roles/cloudsql.client", "roles/cloudsql.instanceUser"]

  iam_grants = {
    for pair in setproduct(local.iam_roles, tolist(var.iam_members)) :
    "${pair[0]}/${pair[1]}" => {
      role   = pair[0]
      member = pair[1]
    }
  }

  # Built from input values (not resource attributes) so the condition is
  # known at plan time.
  instance_resource_names = concat(
    ["projects/${var.project_id}/instances/${var.name}"],
    [for k in sort(keys(local.replica_names)) : "projects/${var.project_id}/instances/${local.replica_names[k]}"],
  )

  iam_condition_expression = format(
    "resource.type == \"sqladmin.googleapis.com/Instance\" && (%s)",
    join(" || ", [for n in local.instance_resource_names : "resource.name == \"${n}\""]),
  )
}

resource "google_sql_user" "iam" {
  for_each = local.iam_database_users

  project  = var.project_id
  instance = google_sql_database_instance.primary.name
  name     = each.value.name
  type     = each.value.type
}

# Additive, per-member grants: the module never takes ownership of the
# project's IAM policy or of a role's full member list.
resource "google_project_iam_member" "instance_access" {
  for_each = local.iam_grants

  project = var.project_id
  role    = each.value.role
  member  = each.value.member

  condition {
    title       = "cloudsql-${var.name}"
    description = "Limits the grant to Cloud SQL instance ${var.name} and its read replicas. Managed by OpenTofu."
    expression  = local.iam_condition_expression
  }

  # Grant access only once the instance exists.
  depends_on = [google_sql_database_instance.primary]
}
