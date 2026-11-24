locals {
  # Network team VPC & regional subnet conventions
  vpc_name                      = "apps-${var.environment}"
  subnet_name                   = "${local.vpc_name}-gke-${var.region}"
  vpc_self_link                 = "projects/${var.project_id}/global/networks/${local.vpc_name}"
  subnet_self_link              = "projects/${var.project_id}/regions/${var.region}/subnetworks/${local.subnet_name}"
  pods_secondary_range_name     = "pods"
  services_secondary_range_name = "services"

  # Workload Identity pool for the project
  workload_identity_pool = "${var.project_id}.svc.id.goog"

  # Deterministic 6-30 char GCP service account ID scoped to this cluster
  node_sa_account_id = "${trim(substr("gke-${var.cluster_name}", 0, 21), "-")}-${substr(md5(var.cluster_name), 0, 6)}"

  # Least-privilege node IAM roles in the cluster project:
  # - roles/container.defaultNodeServiceAccount covers logging, monitoring, metadata, and autoscaling metrics
  # - roles/artifactregistry.reader permits pulling container images from Artifact Registry in the project
  node_sa_project_roles = toset([
    "roles/container.defaultNodeServiceAccount",
    "roles/artifactregistry.reader",
  ])

  # Workload Identity service accounts managed by this module vs pre-existing
  managed_workload_identities = {
    for k, v in var.workload_identities : k => v
    if v.existing_gsa_email == null
  }

  managed_wi_account_ids = {
    for k, _ in local.managed_workload_identities :
    k => "${trim(substr("wi-${k}", 0, 21), "-")}-${substr(md5("${var.cluster_name}/${k}"), 0, 6)}"
  }

  managed_wi_role_bindings = merge([
    for k, v in local.managed_workload_identities : {
      for role in toset(v.project_roles) :
      "${k}:${role}" => {
        wi_key = k
        role   = role
      }
    }
  ]...)

  default_labels = {
    environment = var.environment
    managed_by  = "opentofu"
    cluster     = var.cluster_name
  }

  effective_labels = merge(local.default_labels, var.labels)
}
