# ------------------------------------------------------------------------------
# Dedicated Least-Privilege Service Account for GKE Nodes
# ------------------------------------------------------------------------------
# Every cluster gets its own node service account rather than using the overly
# permissive Compute Engine default service account. Workloads authenticate to
# GCP services (Pub/Sub, Cloud Storage, Cloud SQL, etc.) via Workload Identity
# Federation rather than inheriting node permissions.

resource "google_service_account" "nodes" {
  project      = var.project_id
  account_id   = local.node_sa_account_id
  display_name = "GKE node service account for ${var.cluster_name}"
  description  = "Least-privilege service account for GKE nodes in cluster ${var.cluster_name} (${var.environment}/${var.region})."
}

resource "google_project_iam_member" "node_sa_roles" {
  for_each = local.node_sa_roles

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.nodes.email}"
}
