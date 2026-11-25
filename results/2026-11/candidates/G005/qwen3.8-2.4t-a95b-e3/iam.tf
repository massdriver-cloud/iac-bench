# Least-privilege node service account: nodes only get what GKE requires to
# ship logs/metrics, read metadata and pull images. Workloads themselves reach
# Pub/Sub, Cloud Storage and Cloud SQL through Workload Identity, not through
# this account.
resource "google_service_account" "nodes" {
  project      = local.project_id
  account_id   = local.node_service_account_id
  display_name = "GKE node account for cluster ${var.cluster_name}"
}

resource "google_project_iam_member" "node_roles" {
  for_each = local.node_service_account_roles

  project = local.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.nodes.email}"
}
