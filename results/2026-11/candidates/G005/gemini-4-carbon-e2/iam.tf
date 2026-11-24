# -----------------------------------------------------------------------------
# Dedicated Least-Privilege GKE Node Service Account
# -----------------------------------------------------------------------------

resource "google_service_account" "nodes" {
  project      = var.project_id
  account_id   = local.node_sa_account_id
  display_name = "GKE node service account for ${var.cluster_name} (${var.environment})"
  description  = "Least-privilege Compute Engine service account used by worker nodes in GKE cluster ${var.cluster_name}."
}

resource "google_project_iam_member" "nodes" {
  for_each = local.node_sa_roles

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.nodes.email}"
}

# -----------------------------------------------------------------------------
# Optional Workload Identity Bindings (Pub/Sub, Cloud Storage, Cloud SQL, etc.)
# -----------------------------------------------------------------------------

resource "google_service_account" "workload" {
  for_each = local.managed_workload_identities

  project      = var.project_id
  account_id   = each.value.account_id
  display_name = coalesce(each.value.display_name, "GKE workload ${each.value.namespace}/${each.value.k8s_service_account} (${var.cluster_name})")
  description  = "Workload Identity service account for ${each.value.namespace}/${each.value.k8s_service_account} on GKE cluster ${var.cluster_name}."
}

resource "google_service_account_iam_member" "workload_identity_user" {
  for_each = var.workload_identities

  service_account_id = (
    each.value.gcp_service_account_email != null
    ? "projects/${var.project_id}/serviceAccounts/${each.value.gcp_service_account_email}"
    : google_service_account.workload[each.key].name
  )
  role   = "roles/iam.workloadIdentityUser"
  member = "serviceAccount:${local.workload_identity_pool}[${each.value.namespace}/${each.value.k8s_service_account}]"
}

resource "google_project_iam_member" "workload" {
  for_each = local.workload_identity_project_role_bindings

  project = var.project_id
  role    = each.value.role
  member = format(
    "serviceAccount:%s",
    var.workload_identities[each.value.wi_key].gcp_service_account_email != null
    ? var.workload_identities[each.value.wi_key].gcp_service_account_email
    : google_service_account.workload[each.value.wi_key].email
  )
}
