locals {
  node_sa_roles = [
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/monitoring.viewer",
    "roles/stackdriver.resourceMetadata.writer",
    "roles/artifactregistry.reader"
  ]

  node_service_account_email = var.node_service_account != null ? var.node_service_account : google_service_account.cluster_node[0].email
}

resource "google_service_account" "cluster_node" {
  count        = var.node_service_account == null ? 1 : 0
  project      = var.project_id
  account_id   = trimsuffix(substr(lower("${var.cluster_name}-node-sa"), 0, 30), "-")
  display_name = "GKE Node Service Account - ${var.cluster_name}"
  description  = "Dedicated least-privilege service account for GKE cluster ${var.cluster_name} nodes"
}

resource "google_project_iam_member" "cluster_node_roles" {
  for_each = var.node_service_account == null ? toset(local.node_sa_roles) : toset([])
  project  = var.project_id
  role     = each.value
  member   = "serviceAccount:${google_service_account.cluster_node[0].email}"
}
