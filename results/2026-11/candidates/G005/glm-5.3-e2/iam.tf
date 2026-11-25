# ===========================================================================
# Node service account
# ===========================================================================
#
# Every cluster gets its own node service account, created here, instead of
# the project-wide default compute account. It carries only what nodes
# themselves need (log and metric shipping); product workloads never use it
# because Workload Identity gives each Kubernetes service account its own
# Google identity.

resource "google_service_account" "nodes" {
  provider = google

  account_id   = "gke-${var.name}"
  display_name = "GKE nodes: ${var.name}"
  description  = "Node service account for GKE cluster ${var.name}. Pods should use Workload Identity instead of these credentials."
}

resource "google_project_iam_member" "node_sa" {
  provider = google

  for_each = toset([
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/stackdriver.resourceMetadata.writer",
  ])

  project = var.project_id
  role    = each.key
  member  = "serviceAccount:${google_service_account.nodes.email}"
}

# ===========================================================================
# Workload Identity bindings
# ===========================================================================
#
# Grants the Kubernetes service account <namespace>/<map key> in this cluster
# the ability to act as a Google service account, so workloads can reach
# Pub/Sub, Cloud Storage, Cloud SQL etc. with their own identity.

resource "google_service_account_iam_member" "workload_identity" {
  provider = google

  for_each = var.workload_identity_bindings

  service_account_id = "projects/${var.project_id}/serviceAccounts/${each.value.service_account}"
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[${each.value.namespace}/${each.key}]"
}
