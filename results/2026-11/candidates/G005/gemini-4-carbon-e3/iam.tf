# -----------------------------------------------------------------------------
# Dedicated Least-Privilege GKE Node Service Account
# -----------------------------------------------------------------------------

resource "google_service_account" "nodes" {
  project      = var.project_id
  account_id   = local.node_sa_account_id
  display_name = "GKE nodes (${var.cluster_name})"
  description  = "Least-privilege Compute Engine service account for GKE cluster ${var.cluster_name} in ${var.region}."
}

resource "google_project_iam_member" "nodes" {
  for_each = local.node_sa_project_roles

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.nodes.email}"
}

resource "google_project_iam_member" "nodes_artifact_registry" {
  for_each = toset(var.artifact_registry_projects)

  project = each.value
  role    = "roles/artifactregistry.reader"
  member  = "serviceAccount:${google_service_account.nodes.email}"
}

# -----------------------------------------------------------------------------
# Optional Workload Identity Bindings (Cloud SQL, Pub/Sub, Cloud Storage, etc.)
# -----------------------------------------------------------------------------

resource "google_service_account" "workload" {
  for_each = local.managed_workload_identities

  project      = var.project_id
  account_id   = local.managed_wi_account_ids[each.key]
  display_name = "GKE WI ${var.cluster_name}/${each.key}"
  description  = coalesce(each.value.description, "Workload Identity service account for ${each.value.namespace}/${each.value.k8s_service_account} on GKE cluster ${var.cluster_name}.")
}

resource "google_project_iam_member" "workload" {
  for_each = local.managed_wi_role_bindings

  project = var.project_id
  role    = each.value.role
  member  = "serviceAccount:${google_service_account.workload[each.value.wi_key].email}"
}

resource "google_service_account_iam_member" "workload_identity_user" {
  for_each = var.workload_identities

  service_account_id = (
    each.value.existing_gsa_email != null
    ? "projects/-/serviceAccounts/${each.value.existing_gsa_email}"
    : google_service_account.workload[each.key].name
  )
  role   = "roles/iam.workloadIdentityUser"
  member = "serviceAccount:${local.workload_identity_pool}[${each.value.namespace}/${each.value.k8s_service_account}]"

  depends_on = [google_container_cluster.this]
}
