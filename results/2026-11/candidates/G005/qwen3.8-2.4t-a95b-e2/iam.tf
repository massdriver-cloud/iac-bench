# -----------------------------------------------------------------------------
# Dedicated, least-privilege service account for cluster nodes.
#
# Nodes get only what they need to run (logging, monitoring, pulling images).
# Product workloads must not rely on this identity: each team maps its
# Kubernetes service accounts to its own Google service accounts using
# Workload Identity (see the workload_identity_pool output).
# -----------------------------------------------------------------------------
resource "google_service_account" "nodes" {
  project      = var.project_id
  account_id   = local.node_sa_account_id
  display_name = "GKE nodes for ${var.cluster_name}"
  description  = "Node service account for the ${var.cluster_name} GKE cluster (managed by the platform GKE module)."
}

resource "google_project_iam_member" "nodes" {
  for_each = toset(var.node_sa_roles)

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.nodes.email}"
}
