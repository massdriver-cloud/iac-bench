locals {
  vpc_name        = "apps-${var.environment}"
  subnetwork_name = "${local.vpc_name}-gke-${var.region}"

  network_self_link    = "projects/${var.project_id}/global/networks/${local.vpc_name}"
  subnetwork_self_link = "projects/${var.project_id}/regions/${var.region}/subnetworks/${local.subnetwork_name}"

  cluster_labels = merge(
    {
      environment = var.environment
      managed_by  = "opentofu"
      cluster     = var.cluster_name
    },
    var.labels,
  )

  raw_node_sa_id = "${var.cluster_name}-nodes"
  node_sa_id     = length(local.raw_node_sa_id) <= 30 ? local.raw_node_sa_id : "${trimsuffix(substr(var.cluster_name, 0, 20), "-")}-${substr(md5(var.cluster_name), 0, 5)}-gke"

  base_node_sa_roles = [
    "roles/container.defaultNodeServiceAccount",
    "roles/artifactregistry.reader",
  ]

  node_sa_roles = toset(concat(local.base_node_sa_roles, var.additional_node_sa_roles))
}
