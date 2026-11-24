resource "google_service_account" "workloads" {
  for_each = var.workload_service_accounts

  project      = var.project_id
  account_id   = each.key
  display_name = coalesce(each.value.display_name, "GKE workload ${each.key} (${var.cluster_name})")
  description  = coalesce(each.value.description, "Application identity for Kubernetes workloads on ${var.cluster_name}; managed by OpenTofu.")

  depends_on = [google_project_service.required]
}

locals {
  workload_project_role_bindings = flatten([
    for account_id, account in var.workload_service_accounts : [
      for role in account.project_roles : {
        key        = "${account_id}:${role}"
        account_id = account_id
        role       = role
      }
    ]
  ])

  workload_identity_bindings = flatten([
    for account_id, account in var.workload_service_accounts : [
      for identity in account.kubernetes_service_accounts : {
        key        = "${account_id}:${identity}"
        account_id = account_id
        identity   = identity
      }
    ]
  ])
}

resource "google_project_iam_member" "workload_roles" {
  for_each = { for binding in local.workload_project_role_bindings : binding.key => binding }

  project = var.project_id
  role    = each.value.role
  member  = google_service_account.workloads[each.value.account_id].member
}

resource "google_service_account_iam_member" "workload_identity" {
  for_each = { for binding in local.workload_identity_bindings : binding.key => binding }

  service_account_id = google_service_account.workloads[each.value.account_id].name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[${each.value.identity}]"

  # Ensure the cluster's Workload Identity pool exists before adding members
  # whose principal names are scoped to that pool.
  depends_on = [google_container_cluster.this]
}
