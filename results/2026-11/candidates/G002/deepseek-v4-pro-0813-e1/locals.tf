locals {
  # Cloud SQL instance names must be lowercase alphanumeric/hyphen.
  # Use a random suffix so repeated applies in the same project don't collide
  # when a name is reused before the old instance is fully deleted.
  instance_name = lower(replace("${var.name}-${random_id.suffix.hex}", "_", "-"))

  # The network team owns the VPC and private services access on each network,
  # so this module references the network by its fully-qualified resource link
  # rather than managing (or reading) it.
  private_network = "projects/${var.project_id}/global/networks/${var.network_name}"

  # Flags that are identical on every instance. IAM authentication is what lets
  # applications connect with their Google identity instead of a stored password,
  # which is how the security team audits access. Base flags win over
  # user-supplied flags so this invariant cannot be silently disabled.
  base_flags = {
    "cloudsql.iam_authentication" = "on"
  }

  combined_flags = merge(var.database_flags, local.base_flags)

  default_labels = {
    app         = "cloud-sql-postgres"
    environment = var.environment
    managed-by  = "opentofu"
  }
  all_labels = merge(local.default_labels, var.labels)
}

resource "random_id" "suffix" {
  byte_length = 4
  keepers = {
    name    = var.name
    project = var.project_id
  }
}