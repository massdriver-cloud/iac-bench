# ---------------------------------------------------------------------------
# Dedicated, least-privilege node service account. Nodes must never run as the
# Compute Engine default service account (which is Editor on most projects).
# Workload Identity means application pods get their own identities; these
# roles are only what the kubelet/node agents need.
# ---------------------------------------------------------------------------

resource "google_service_account" "nodes" {
  account_id   = local.node_service_account_id
  display_name = "GKE nodes for ${var.cluster_name} (${var.environment})"
  description  = "Least-privilege node identity managed by the GKE platform module."
}

resource "google_project_iam_member" "node_roles" {
  for_each = toset([
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/monitoring.viewer",
    "roles/stackdriver.resourceMetadata.writer",
    "roles/artifactregistry.reader",
  ])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.nodes.email}"
}
