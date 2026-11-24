locals {
  vpc_name    = "apps-${var.environment}"
  subnet_name = "${local.vpc_name}-gke-${var.region}"

  network_id = "projects/${var.project_id}/global/networks/${local.vpc_name}"
  subnet_id  = "projects/${var.project_id}/regions/${var.region}/subnetworks/${local.subnet_name}"

  # Build a collision-resistant, GCP-compliant (6-30 char) service account ID.
  sa_prefix          = trim(substr("gke-${var.cluster_name}", 0, 19), "-")
  sa_hash            = substr(md5(var.cluster_name), 0, 4)
  node_sa_account_id = "${local.sa_prefix}-${local.sa_hash}-nodes"

  common_labels = merge(
    {
      environment = var.environment
      cluster     = var.cluster_name
      managed_by  = "opentofu"
    },
    var.labels
  )

  node_sa_roles = toset([
    "roles/container.defaultNodeServiceAccount",
    "roles/artifactregistry.reader",
  ])
}
