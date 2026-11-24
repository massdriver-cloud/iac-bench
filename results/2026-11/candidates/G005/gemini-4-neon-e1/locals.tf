locals {
  # Network conventions owned by the network team:
  # - One VPC per environment: apps-staging, apps-prod
  # - One pre-created GKE subnet per US region: <vpc>-gke-<region>
  # - Secondary IP ranges named 'pods' and 'services'
  vpc_name                      = "apps-${var.environment}"
  subnet_name                   = "${local.vpc_name}-gke-${var.region}"
  network_self_link             = "projects/${var.project_id}/global/networks/${local.vpc_name}"
  subnetwork_self_link          = "projects/${var.project_id}/regions/${var.region}/subnetworks/${local.subnet_name}"
  pods_secondary_range_name     = "pods"
  services_secondary_range_name = "services"

  workload_identity_pool = "${var.project_id}.svc.id.goog"
  cluster_node_tag       = "gke-${var.cluster_name}-node"

  # GCP Service Account IDs must be 6-30 chars (lowercase letters, digits, hyphens).
  # If "<cluster_name>-nodes" exceeds 30 chars, truncate and include a deterministic hash
  # so distinct clusters sharing a long prefix never collide.
  node_sa_id_raw = "${var.cluster_name}-nodes"
  node_sa_account_id = (
    length(local.node_sa_id_raw) <= 30
    ? local.node_sa_id_raw
    : "${trim(substr(var.cluster_name, 0, 17), "-")}-${substr(md5(var.cluster_name), 0, 6)}-nodes"
  )

  # Minimal least-privilege IAM roles required for GKE nodes to emit logs/metrics
  # and pull container images from Artifact Registry.
  # Product-team workloads NEVER use this service account; they authenticate to
  # Pub/Sub, Cloud Storage, Cloud SQL, etc. via Workload Identity Federation.
  node_sa_roles = toset([
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/monitoring.viewer",
    "roles/stackdriver.resourceMetadata.writer",
    "roles/artifactregistry.reader",
  ])

  common_labels = merge(
    {
      environment = var.environment
      cluster     = var.cluster_name
      managed_by  = "opentofu"
    },
    var.labels,
  )
}
