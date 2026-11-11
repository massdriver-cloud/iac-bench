###############################################################################
# Derived values
###############################################################################

locals {
  # The network team runs one custom VPC per environment with private services
  # access already configured. The environment -> network mapping is
  # deterministic, so it lives here instead of being an input.
  network_name       = "apps-${var.environment}"
  network_project_id = coalesce(var.network_project_id, var.project_id)
  private_network    = "https://www.googleapis.com/compute/v1/projects/${local.network_project_id}/global/networks/${local.network_name}"

  database_version = "POSTGRES_${var.major_version}"

  # The things that should be the same everywhere are policy keyed by
  # environment, not per-instance decisions. Each of them has an escape-hatch
  # variable for the rare case that genuinely calls for one.
  environment_policy = {
    dev = {
      availability_type              = "ZONAL"
      backup_retention_days          = 7
      transaction_log_retention_days = 1
    }
    staging = {
      availability_type              = "REGIONAL"
      backup_retention_days          = 14
      transaction_log_retention_days = 7
    }
    prod = {
      availability_type              = "REGIONAL"
      backup_retention_days          = 30
      transaction_log_retention_days = 7
    }
  }
  policy = local.environment_policy[var.environment]

  availability_type              = coalesce(var.availability_type, local.policy.availability_type)
  backup_retention_days          = coalesce(var.backup_retention_days, local.policy.backup_retention_days)
  transaction_log_retention_days = coalesce(var.transaction_log_retention_days, local.policy.transaction_log_retention_days)

  labels = merge(
    var.labels,
    {
      environment = var.environment
      managed_by  = "opentofu"
    },
  )

  # IAM database authentication is the module's only authentication mechanism.
  database_flags = merge(
    var.database_flags,
    { "cloudsql.iam_authentication" = "on" },
  )
}
