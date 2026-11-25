data "google_client_config" "current" {}

locals {
  # Explicit project wins; otherwise the project configured in the environment.
  project_id = try(coalesce(var.project_id, data.google_client_config.current.project), "")

  # Network team conventions: one VPC per environment, one GKE subnet per region,
  # secondary ranges "pods" and "services". Referenced by name so nothing here
  # can modify what the network team owns.
  vpc_name    = "apps-${var.environment}"
  subnet_name = "${local.vpc_name}-gke-${var.region}"
  network     = "projects/${local.project_id}/global/networks/${local.vpc_name}"
  subnetwork  = "projects/${local.project_id}/regions/${var.region}/subnetworks/${local.subnet_name}"

  pods_range_name     = "pods"
  services_range_name = "services"

  # Staging takes new GKE versions first; prod follows on the slower channel.
  release_channel = coalesce(var.release_channel, var.environment == "prod" ? "STABLE" : "REGULAR")

  labels = merge(var.labels, {
    environment = var.environment
    cluster     = var.name
    managed-by  = "opentofu"
  })

  # Network tag on every node, so firewall rules can target this cluster's nodes.
  node_network_tag = "gke-${var.name}-node"

  # Service account IDs are limited to 30 characters; keep the name readable and
  # add a short hash so clusters with the same name in different regions don't collide.
  node_service_account_id = "gke-${substr(var.name, 0, 19)}-${substr(sha1("${var.region}/${var.name}"), 0, 6)}"

  node_service_account_roles = [
    "roles/container.defaultNodeServiceAccount", # write logs and metrics, nothing else
    "roles/artifactregistry.reader",             # pull images from this project's repositories
  ]
}

###############################################################################
# API
###############################################################################

resource "google_project_service" "container" {
  project = local.project_id
  service = "container.googleapis.com"

  # Other clusters in the project depend on the API; never switch it off from here.
  disable_on_destroy = false

  lifecycle {
    precondition {
      condition     = local.project_id != ""
      error_message = "No project is set. Set project_id, or set GOOGLE_PROJECT in the environment."
    }
  }
}

###############################################################################
# Node identity
#
# Nodes run as a dedicated, least-privilege service account instead of the
# Compute Engine default one. Workloads do not use this identity to reach
# Google Cloud services: they use Workload Identity Federation for GKE.
###############################################################################

resource "google_service_account" "nodes" {
  project      = local.project_id
  account_id   = local.node_service_account_id
  display_name = "GKE nodes: ${var.name} (${var.region})"
  description  = "Least-privilege identity for the nodes of GKE cluster ${var.name} in ${var.region}. Not for workloads."
}

resource "google_project_iam_member" "nodes" {
  for_each = toset(local.node_service_account_roles)

  project = local.project_id
  role    = each.value
  member  = google_service_account.nodes.member
}
