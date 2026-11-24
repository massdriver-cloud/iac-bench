resource "google_service_account" "nodes" {
  account_id   = "gke-${substr(var.cluster_name, 0, 17)}-${substr(sha1(var.cluster_name), 0, 6)}"
  display_name = "GKE nodes for ${var.cluster_name}"
  description  = "Least-privilege node identity for ${var.cluster_name}; workload identities are bound separately."
  project      = var.project_id

  depends_on = [google_project_service.required]
}

# These are operational permissions required by GKE nodes. In particular, the
# node identity receives no Pub/Sub, Cloud Storage object, or Cloud SQL access:
# application permissions belong to per-workload Google service accounts.
resource "google_project_iam_member" "node_operations" {
  for_each = toset([
    "roles/artifactregistry.reader",
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/monitoring.viewer",
    "roles/stackdriver.resourceMetadata.writer",
  ])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.nodes.email}"
}

locals {
  workload_identity_bindings = {
    for key, binding in var.workload_identity_bindings : key => merge(binding, {
      google_service_account_id = "projects/${trimsuffix(split("@", binding.google_service_account_email)[1], ".iam.gserviceaccount.com")}/serviceAccounts/${binding.google_service_account_email}"
      workload_identity_member  = "serviceAccount:${var.project_id}.svc.id.goog[${binding.namespace}/${binding.kubernetes_service_account}]"
    })
  }
}

# Non-authoritative IAM members allow multiple product teams to share a Google
# service account where appropriate without overwriting one another's bindings.
resource "google_service_account_iam_member" "workload_identity" {
  for_each = local.workload_identity_bindings

  service_account_id = each.value.google_service_account_id
  role               = "roles/iam.workloadIdentityUser"
  member             = each.value.workload_identity_member

  depends_on = [google_container_cluster.this]
}
