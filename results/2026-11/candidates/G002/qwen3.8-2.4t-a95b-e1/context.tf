###############################################################################
# Current GCP context
#
# Credentials (and, when set, a fallback project) come from the environment.
# DBAs can pin an explicit project via var.project_id instead.
###############################################################################

data "google_client_config" "current" {}

locals {
  project_id         = var.project_id != null ? var.project_id : data.google_client_config.current.project
  network_project_id = var.network_project_id != null ? var.network_project_id : local.project_id

  # One network per environment, owned and peered (private services access)
  # by the network team. The module only consumes it — it never touches the
  # network or its PSA ranges.
  network_name      = "apps-${var.environment}"
  network_self_link = "projects/${local.network_project_id}/global/networks/${local.network_name}"
}
