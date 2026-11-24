resource "google_service_account" "nodes" {
  project      = var.project_id
  account_id   = local.node_service_account_id
  display_name = "GKE nodes: ${var.cluster_name}"
  description  = "Least-privilege identity for nodes in ${var.cluster_name}; application workloads use separate Workload Identity accounts."

  depends_on = [google_project_service.required]
}

# OAuth scopes do not grant permissions by themselves. These roles are the
# operational baseline for GKE nodes and Artifact Registry image pulls; broad
# storage, Pub/Sub, SQL, and owner/editor permissions are intentionally absent.
resource "google_project_iam_member" "node" {
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

resource "google_service_account" "workload" {
  for_each = var.workload_service_accounts

  project      = var.project_id
  account_id   = each.key
  display_name = coalesce(each.value.display_name, "GKE workload: ${each.key}")
  description  = "Workload Identity account for ${each.value.kubernetes_namespace}/${each.value.kubernetes_service_account} in ${var.cluster_name}."

  depends_on = [google_project_service.required]
}

resource "google_service_account_iam_member" "workload_identity" {
  for_each = var.workload_service_accounts

  service_account_id = google_service_account.workload[each.key].name
  role               = "roles/iam.workloadIdentityUser"
  member = (
    "serviceAccount:${var.project_id}.svc.id.goog[${each.value.kubernetes_namespace}/${each.value.kubernetes_service_account}]"
  )
}

locals {
  workload_project_role_bindings = flatten([
    for account_id, account in var.workload_service_accounts : [
      for role in account.project_roles : {
        key        = "${account_id}|${role}"
        account_id = account_id
        role       = role
      }
    ]
  ])
}

resource "google_project_iam_member" "workload" {
  for_each = {
    for binding in local.workload_project_role_bindings : binding.key => binding
  }

  project = var.project_id
  role    = each.value.role
  member  = "serviceAccount:${google_service_account.workload[each.value.account_id].email}"
}
