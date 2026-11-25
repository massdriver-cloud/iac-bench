locals {
  # The network team owns one VPC per environment (apps-dev, apps-staging,
  # apps-prod) with Private Service Access already allocated on each. The
  # environment therefore determines the network deterministically; nobody
  # picks or types a network name.
  network_project = coalesce(var.network_project, var.project)
  private_network = "https://www.googleapis.com/compute/v1/projects/${local.network_project}/global/networks/apps-${var.environment}"

  # Posture that is the same on every instance. Callers may add flags, but
  # these are locked and always win.
  locked_database_flags = {
    "cloudsql.iam_authentication" = "on" # database access is by Google identity, auditable as such
    "log_connections"             = "on" # security team audits access per identity
    "log_disconnections"          = "on"
  }
  database_flags = merge(var.database_flags, local.locked_database_flags)

  labels = merge(var.labels, {
    env        = var.environment
    managed-by = "opentofu"
  })
}
