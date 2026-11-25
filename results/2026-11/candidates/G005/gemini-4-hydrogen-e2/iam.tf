resource "google_service_account" "gke_nodes" {
  account_id   = local.node_sa_account_id
  display_name = "GKE node service account for ${var.cluster_name}"
  description  = "Least-privilege service account for GKE nodes in cluster ${var.cluster_name}. Workloads must use Workload Identity."
  project      = var.project_id
}

resource "google_project_iam_member" "gke_nodes" {
  for_each = local.node_sa_roles

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.gke_nodes.email}"
}
