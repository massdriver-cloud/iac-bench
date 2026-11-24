resource "google_service_account" "nodes" {
  project      = local.project_id
  account_id   = local.node_sa_account_id
  display_name = "GKE node service account for ${var.cluster_name} (${var.region})"
  description  = "Least-privilege node identity for GKE Standard cluster ${var.cluster_name} in ${var.region}. Workloads authenticate via Workload Identity Federation instead."
}

# Google's minimal curated IAM role for GKE worker nodes (logging, monitoring,
# autoscaling metrics, and resource metadata).
resource "google_project_iam_member" "node_default" {
  project = local.project_id
  role    = "roles/container.defaultNodeServiceAccount"
  member  = "serviceAccount:${google_service_account.nodes.email}"
}

# Allow nodes to pull container images from Artifact Registry repositories.
resource "google_project_iam_member" "node_artifact_registry_reader" {
  for_each = local.artifact_registry_projects

  project = each.value
  role    = "roles/artifactregistry.reader"
  member  = "serviceAccount:${google_service_account.nodes.email}"
}
