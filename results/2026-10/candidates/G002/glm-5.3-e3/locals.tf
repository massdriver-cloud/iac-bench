###############################################################################
# Derived values.
#
# This is where the "same everywhere" decisions live, as data rather than
# variables: nobody should be able to turn IAM authentication off, drop the
# baseline labels or weaken the standard by passing a clever value.
###############################################################################

locals {
  # Baseline labels on every resource this module owns.
  labels = merge(var.labels, {
    managed_by = "opentofu"
    module     = "dba-cloud-sql-postgres"
  })

  # IAM database authentication is part of the access standard: the flag is
  # always on and always first in the list. var.database_flags cannot
  # override it (blocked by a variable validation).
  database_flags = concat(
    [{ name = "cloudsql.iam_authentication", value = "on" }],
    [for name, value in var.database_flags : { name = name, value = value }],
  )

  # Cloud SQL distinguishes human identities (IAM_USER) from service-account
  # identities (IAM_SERVICE_ACCOUNT). Infer the type from the email unless the
  # caller is explicit - mechanical, not a decision.
  iam_users = {
    for name, cfg in var.iam_users :
    name => {
      type = cfg.type != null ? cfg.type : (endswith(lower(name), ".iam.gserviceaccount.com") ? "IAM_SERVICE_ACCOUNT" : "IAM_USER")
    }
  }

  postgres_password_secret_id = "cloudsql-${var.name}-postgres-password"
}
