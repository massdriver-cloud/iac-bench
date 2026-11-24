# ---------------------------------------------------------------------------
# Dedicated node service account (least privilege).
# Nodes never get roles/editor or the compute default SA; workload access to
# Google APIs goes through Workload Identity instead.
# ---------------------------------------------------------------------------

resource "google_service_account" "nodes" {
  project      = var.project_id
  account_id   = "gke-${var.cluster_name}-nodes"
  display_name = "GKE nodes for ${var.cluster_name} (${var.environment})"
  description  = "Least-privilege node identity managed by the platform GKE module."
}

resource "google_project_iam_member" "nodes" {
  for_each = toset(local.node_service_account_roles)

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.nodes.email}"
}

# ---------------------------------------------------------------------------
# Workload Identity for product-team workloads.
# For each entry: a Google service account, its project-level role grants
# (Pub/Sub, Cloud Storage, Cloud SQL, ...), and a keyless binding that lets
# exactly one Kubernetes service account impersonate it.
# ---------------------------------------------------------------------------

resource "google_service_account" "workload" {
  for_each = var.workload_identities

  project      = var.project_id
  account_id   = "wi-${each.key}"
  display_name = "Workload identity ${each.key} on ${var.cluster_name}"
  description  = "Bound to KSA ${each.value.namespace}/${each.value.ksa_name} via GKE Workload Identity."
}

locals {
  # "<identity-key>/<role>" => { identity, role }
  workload_role_bindings = merge([
    for key, wi in var.workload_identities : {
      for role in wi.roles : "${key}/${role}" => {
        identity = key
        role     = role
      }
    }
  ]...)
}

resource "google_project_iam_member" "workload" {
  for_each = local.workload_role_bindings

  project = var.project_id
  role    = each.value.role
  member  = "serviceAccount:${google_service_account.workload[each.value.identity].email}"
}

resource "google_service_account_iam_member" "workload_binding" {
  for_each = var.workload_identities

  service_account_id = google_service_account.workload[each.key].name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${local.workload_identity_pool}[${each.value.namespace}/${each.value.ksa_name}]"
}
