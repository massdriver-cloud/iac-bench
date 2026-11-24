# ---------------------------------------------------------------------------
# Node service account: module-managed, minimal, never the Compute default SA.
# Workloads do NOT use it for data access — they get dedicated Google service
# accounts through Workload Identity (see workload_identity_pool output).
# ---------------------------------------------------------------------------

resource "google_service_account" "nodes" {
  project      = var.project_id
  account_id   = local.node_sa_id
  display_name = "GKE node service account for ${var.cluster_name}"
  description  = "Managed by the GKE Standard platform module. Used by every node pool unless a pool overrides service_account."
}

resource "google_project_iam_member" "node_sa_roles" {
  for_each = toset(local.node_sa_roles)

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.nodes.email}"
}
