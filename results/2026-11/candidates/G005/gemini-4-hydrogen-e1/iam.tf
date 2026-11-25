resource "google_service_account" "nodes" {
  project      = var.project_id
  account_id   = local.node_sa_account_id
  display_name = "GKE node service account for ${var.cluster_name}"
  description  = "Dedicated least-privilege service account used by GKE nodes in cluster ${var.cluster_name} (${var.environment})."
}

resource "google_project_iam_member" "nodes" {
  for_each = local.node_sa_roles

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.nodes.email}"
}
