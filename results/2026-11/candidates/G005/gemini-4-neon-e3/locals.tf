locals {
  project_id = coalesce(var.project_id, data.google_client_config.current.project)

  # Network team conventions:
  # - One VPC per environment: apps-staging, apps-prod
  # - Regional GKE subnet: <vpc>-gke-<region>
  # - Secondary ranges: pods, services
  vpc_name            = "apps-${var.environment}"
  subnet_name         = "${local.vpc_name}-gke-${var.region}"
  pods_range_name     = "pods"
  services_range_name = "services"

  workload_identity_pool = "${local.project_id}.svc.id.goog"

  # Deterministically derive a /28 control plane CIDR inside 172.16.0.0/12
  # (65,536 possible /28 blocks) from cluster_name + region when not explicitly
  # supplied, avoiding manual CIDR bookkeeping while staying clear of the network
  # team's 10.x.x.x VPC space.
  master_cidr_index = parseint(substr(sha256("${var.cluster_name}-${var.region}"), 0, 4), 16)
  master_ipv4_cidr_block = coalesce(
    var.master_ipv4_cidr_block,
    cidrsubnet("172.16.0.0/12", 16, local.master_cidr_index)
  )

  # GCP service account IDs must be 6-30 characters, lowercase alphanumeric/hyphens,
  # starting with a letter and ending with a letter or digit.
  sa_prefix          = trimsuffix(substr("gke-${var.cluster_name}", 0, 21), "-")
  sa_suffix          = substr(sha256("${var.cluster_name}-${var.region}"), 0, 8)
  node_sa_account_id = "${local.sa_prefix}-${local.sa_suffix}"

  node_network_tag = "gke-${var.cluster_name}"

  common_labels = merge(
    var.labels,
    {
      environment = var.environment
      cluster     = var.cluster_name
      managed-by  = "opentofu"
    }
  )

  artifact_registry_projects = toset(concat(
    var.grant_artifact_registry_reader ? [local.project_id] : [],
    var.artifact_registry_projects
  ))

  subnet_secondary_range_names = [
    for r in data.google_compute_subnetwork.subnet.secondary_ip_range : r.range_name
  ]
}
