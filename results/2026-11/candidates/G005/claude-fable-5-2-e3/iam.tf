# Dedicated node identity per cluster. Nodes never run as the Compute Engine
# default service account (which is typically a project Editor).
#
# This account is for the NODES only (kubelet, logging/monitoring agents,
# image pulls). Workloads must not rely on it: they get their own access to
# Pub/Sub, Cloud Storage, Cloud SQL, ... through Workload Identity.
resource "google_service_account" "nodes" {
  project      = local.project_id
  account_id   = "${trimsuffix(substr("gke-${var.name}", 0, 25), "-")}-${random_id.suffix.hex}"
  display_name = "GKE nodes: ${var.name} (${var.region})"
  description  = "Least-privilege node service account for GKE cluster ${var.name} in ${var.region}. Managed by OpenTofu."
}

locals {
  node_service_account_roles = [
    # Minimum a GKE node needs: write logs and metrics, read monitoring config.
    "roles/container.defaultNodeServiceAccount",
    # Pull images from Artifact Registry repositories in this project.
    "roles/artifactregistry.reader",
  ]
}

resource "google_project_iam_member" "nodes" {
  for_each = toset(local.node_service_account_roles)

  project = local.project_id
  role    = each.value
  member  = google_service_account.nodes.member
}
