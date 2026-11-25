locals {
  vpc_name             = "apps-${var.environment}"
  subnet_name          = "${local.vpc_name}-gke-${var.region}"
  network_self_link    = "projects/${var.project_id}/global/networks/${local.vpc_name}"
  subnetwork_self_link = "projects/${var.project_id}/regions/${var.region}/subnetworks/${local.subnet_name}"

  workload_identity_pool = "${var.project_id}.svc.id.goog"

  # Project-global GSA account_ids must be 6-30 chars matching ^[a-z]([-a-z0-9]*[a-z0-9])$.
  # Including region/name in the hash avoids collisions if clusters share names across US regions.
  node_sa_account_id = "gke-${trimsuffix(substr(var.name, 0, 18), "-")}-${substr(md5("${var.region}/${var.name}"), 0, 6)}"

  node_sa_roles = [
    "roles/container.defaultNodeServiceAccount",
    "roles/artifactregistry.reader",
  ]

  managed_workload_identities = {
    for k, wi in var.workload_identities : k => merge(wi, {
      account_id = "wi-${trimsuffix(substr(k, 0, 19), "-")}-${substr(md5("${var.region}/${var.name}/${k}"), 0, 6)}"
    })
    if wi.existing_gsa_email == null
  }

  workload_identity_gsa_emails = {
    for k, wi in var.workload_identities : k => (
      wi.existing_gsa_email != null
      ? wi.existing_gsa_email
      : google_service_account.workload[k].email
    )
  }

  workload_identity_gsa_ids = {
    for k, wi in var.workload_identities : k => (
      wi.existing_gsa_email != null
      ? "projects/-/serviceAccounts/${wi.existing_gsa_email}"
      : google_service_account.workload[k].name
    )
  }

  workload_identity_role_bindings = {
    for item in flatten([
      for k, wi in var.workload_identities : [
        for role in distinct(wi.project_roles) : {
          key          = "${k}:${role}"
          workload_key = k
          role         = role
        }
      ]
    ]) : item.key => item
  }

  common_labels = merge(
    {
      environment = var.environment
      cluster     = var.name
      managed_by  = "opentofu"
    },
    var.labels,
  )

  base_network_tags = [
    "gke-${var.environment}",
    "gke-${var.name}",
  ]
}
