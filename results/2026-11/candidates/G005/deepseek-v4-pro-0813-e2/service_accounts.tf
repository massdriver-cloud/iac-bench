# Dedicated node service account so nodes never run as the broad GCE default SA.
resource "google_service_account" "nodes" {
  account_id   = var.cluster_name
  display_name = "GKE nodes for ${var.cluster_name}"
  project      = var.project_id
}

# Least-privilege roles the cluster's product workloads actually need to talk to
# container registries, emit logs/metrics, and use Workload Identity.
resource "google_project_iam_member" "node_sa_roles" {
  for_each = toset([
    "roles/storage.objectViewer",    # GCR image pulls
    "roles/artifactregistry.reader", # Artifact Registry image pulls
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/monitoring.viewer",
  ])
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.nodes.email}"
}

# Allow the default Kubernetes service account in the default namespace to
# impersonate the node SA, so a cluster starts usable for Workload Identity
# without any extra team-level setup.
resource "google_service_account_iam_member" "node_workload_identity_user" {
  service_account_id = google_service_account.nodes.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[default/default]"
}