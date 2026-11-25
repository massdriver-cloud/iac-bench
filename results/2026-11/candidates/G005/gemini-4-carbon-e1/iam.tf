# -----------------------------------------------------------------------------
# Dedicated Least-Privilege Node Service Account
# -----------------------------------------------------------------------------

resource "google_service_account" "nodes" {
  project      = var.project_id
  account_id   = local.node_sa_account_id
  display_name = "GKE nodes for ${var.name} (${var.region})"
  description  = "Least-privilege Google Service Account for worker nodes in GKE cluster ${var.name} (${var.environment}, ${var.region})."
}

resource "google_project_iam_member" "nodes" {
  for_each = toset(local.node_sa_roles)

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.nodes.email}"
}

# -----------------------------------------------------------------------------
# Workload Identity Service Accounts & Bindings (Pub/Sub, GCS, Cloud SQL, etc.)
# -----------------------------------------------------------------------------

resource "google_service_account" "workload" {
  for_each = local.managed_workload_identities

  project      = var.project_id
  account_id   = each.value.account_id
  display_name = "GKE WI ${var.name}: ${each.value.namespace}/${each.value.ksa_name}"
  description  = each.value.description
}

resource "google_project_iam_member" "workload" {
  for_each = local.workload_identity_role_bindings

  project = var.project_id
  role    = each.value.role
  member  = "serviceAccount:${local.workload_identity_gsa_emails[each.value.workload_key]}"
}

resource "google_service_account_iam_member" "workload_identity_user" {
  for_each = var.workload_identities

  service_account_id = local.workload_identity_gsa_ids[each.key]
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${local.workload_identity_pool}[${each.value.namespace}/${each.value.ksa_name}]"

  # Ensure the project's <project_id>.svc.id.goog Workload Identity pool is
  # initialized by GKE before binding Kubernetes ServiceAccounts to IAM.
  depends_on = [google_container_cluster.this]
}
