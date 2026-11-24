# ---------------------------------------------------------------------------
# Node identity
#
# One dedicated, least-privilege service account per cluster for the nodes.
# It can write telemetry and pull images — nothing more. All application
# access to Google APIs goes through Workload Identity instead.
# ---------------------------------------------------------------------------

resource "google_service_account" "nodes" {
  project      = var.project_id
  account_id   = trimsuffix(substr("${var.name}-gke-nodes", 0, 30), "-")
  display_name = "GKE node identity — ${var.name}"
  description  = "Least-privilege identity for the node pools of GKE cluster ${var.name}. Managed by OpenTofu."
}

locals {
  node_service_account_roles = toset([
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/monitoring.viewer",
    "roles/stackdriver.resourceMetadata.writer",
    "roles/artifactregistry.reader",
  ])
}

resource "google_project_iam_member" "nodes" {
  for_each = local.node_service_account_roles

  project = var.project_id
  role    = each.key
  member  = "serviceAccount:${google_service_account.nodes.email}"
}

# ---------------------------------------------------------------------------
# Workload identity for product teams
#
# For each entry in var.workload_service_accounts: create the GSA, grant its
# project roles, and allow the given Kubernetes service account to act as it.
# Product teams then annotate their KSA with iam.gke.io/gcp-service-account.
# ---------------------------------------------------------------------------

resource "google_service_account" "workload" {
  for_each = var.workload_service_accounts

  project      = var.project_id
  account_id   = each.key
  display_name = coalesce(each.value.display_name, "${each.key} — workload on ${var.name}")
  description  = "Workload identity for ${each.key} on GKE cluster ${var.name}. Managed by OpenTofu."
}

locals {
  workload_role_grants = merge({}, [
    for sa, cfg in var.workload_service_accounts :
    { for role in cfg.project_roles : "${sa}/${role}" => { service_account = sa, role = role } }
  ]...)
}

resource "google_project_iam_member" "workload" {
  for_each = local.workload_role_grants

  project = var.project_id
  role    = each.value.role
  member  = "serviceAccount:${google_service_account.workload[each.value.service_account].email}"
}

resource "google_service_account_iam_member" "workload_identity" {
  for_each = var.workload_service_accounts

  service_account_id = google_service_account.workload[each.key].name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[${each.value.namespace}/${coalesce(each.value.ksa_name, each.key)}]"
}
