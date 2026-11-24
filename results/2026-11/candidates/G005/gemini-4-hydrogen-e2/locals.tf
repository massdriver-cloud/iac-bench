locals {
  vpc_name    = "apps-${var.environment}"
  subnet_name = "${local.vpc_name}-gke-${var.region}"

  network_self_link    = "projects/${var.project_id}/global/networks/${local.vpc_name}"
  subnetwork_self_link = "projects/${var.project_id}/regions/${var.region}/subnetworks/${local.subnet_name}"

  workload_identity_pool = "${var.project_id}.svc.id.goog"

  # Ensure GCP service account ID (6-30 chars) never truncates into a collision or trailing hyphen.
  node_sa_account_id = (
    length("${var.cluster_name}-nodes") <= 30
    ? "${var.cluster_name}-nodes"
    : "${substr(var.cluster_name, 0, 18)}-${substr(md5(var.cluster_name), 0, 5)}-nodes"
  )

  cluster_node_tag = "gke-${var.cluster_name}"

  common_labels = merge(
    {
      managed_by  = "opentofu"
      environment = var.environment
      cluster     = var.cluster_name
    },
    var.labels
  )

  node_sa_roles = toset([
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/monitoring.viewer",
    "roles/stackdriver.resourceMetadata.writer",
    "roles/artifactregistry.reader",
  ])
}
