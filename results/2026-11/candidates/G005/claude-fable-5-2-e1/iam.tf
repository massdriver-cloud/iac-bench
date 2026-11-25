# Dedicated identity for this cluster's nodes, instead of the Compute Engine
# default service account (which is typically a project Editor).
resource "google_service_account" "nodes" {
  project      = local.project_id
  account_id   = "${var.name}-nodes"
  display_name = "GKE nodes - ${var.name}"
  description  = "Node service account for GKE cluster ${var.name} (${var.environment}). Workloads must NOT use it; they use Workload Identity."
}

locals {
  # Only what a node needs: ship logs and metrics, and pull images from
  # Artifact Registry in this project. Access to Pub/Sub, Cloud Storage,
  # Cloud SQL etc. is granted to workloads via Workload Identity, never here.
  node_service_account_roles = [
    "roles/container.defaultNodeServiceAccount",
    "roles/artifactregistry.reader",
  ]
}

resource "google_project_iam_member" "nodes" {
  for_each = toset(local.node_service_account_roles)

  project = local.project_id
  role    = each.value
  member  = google_service_account.nodes.member
}
