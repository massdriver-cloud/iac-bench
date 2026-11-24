locals {
  # Network team naming conventions:
  # - One VPC per environment: apps-staging, apps-prod
  # - Regional GKE subnet: <vpc>-gke-<region>
  # - Secondary ranges: pods, services
  vpc_name            = "apps-${var.environment}"
  subnet_name         = "${local.vpc_name}-gke-${var.region}"
  pods_range_name     = "pods"
  services_range_name = "services"
  workload_pool       = "${var.project_id}.svc.id.goog"
  deletion_protection = var.deletion_protection != null ? var.deletion_protection : (var.environment == "prod")
  node_sa_account_id  = length(var.cluster_name) <= 24 ? "${var.cluster_name}-nodes" : "${trim(substr(var.cluster_name, 0, 19), "-")}-${substr(md5(var.cluster_name), 0, 4)}-nodes"
  artifact_reg_projs  = toset(distinct(concat([var.project_id], var.artifact_registry_project_ids)))
  cluster_network_tag = "gke-${var.cluster_name}"
  webhook_fw_enabled  = var.master_ipv4_cidr_block != null && length(var.additional_control_plane_webhook_ports) > 0

  common_labels = merge(
    var.labels,
    {
      environment = var.environment
      cluster     = var.cluster_name
      managed-by  = "opentofu"
    }
  )

  # Dedicated system pool isolates GKE-managed system workloads (kube-dns,
  # konnectivity, metrics-server, logging/monitoring agents) from noisy
  # product team workloads.
  system_pool = {
    system = {
      name_prefix        = "system-"
      machine_type       = var.system_node_pool.machine_type
      min_count_per_zone = var.system_node_pool.min_count_per_zone
      max_count_per_zone = var.system_node_pool.max_count_per_zone
      disk_size_gb       = var.system_node_pool.disk_size_gb
      disk_type          = var.system_node_pool.disk_type
      spot               = false
      max_pods_per_node  = var.system_node_pool.max_pods_per_node
      enable_gvisor      = false
      upgrade_strategy   = "SURGE"
      max_surge          = 1
      max_unavailable    = 0
      logging_variant    = "DEFAULT"
      labels = {
        "node-role" = "system"
      }
      tags = []
      taints = [
        {
          key    = "components.gke.io/gke-managed-components"
          value  = "true"
          effect = "NO_SCHEDULE"
        }
      ]
    }
  }

  # Normalize workload node pools and keep name_prefix <= 14 chars so Terraform's
  # 26-char unique suffix stays within GCP's 40-char node pool name limit.
  workload_pools = {
    for name, pool in var.workload_node_pools : name => {
      name_prefix        = length(name) <= 13 ? "${name}-" : "${trim(substr(name, 0, 8), "-")}-${substr(md5(name), 0, 4)}-"
      machine_type       = pool.machine_type
      min_count_per_zone = pool.min_count_per_zone
      max_count_per_zone = pool.max_count_per_zone
      disk_size_gb       = pool.disk_size_gb
      disk_type          = pool.disk_type
      spot               = pool.spot
      max_pods_per_node  = coalesce(pool.max_pods_per_node, var.default_max_pods_per_node)
      enable_gvisor      = pool.enable_gvisor
      upgrade_strategy   = pool.upgrade_strategy
      max_surge          = pool.max_surge
      max_unavailable    = pool.max_unavailable
      logging_variant    = pool.logging_variant
      labels = merge(
        {
          "node-role" = "workload"
        },
        pool.labels
      )
      tags = pool.tags
      taints = concat(
        pool.taints,
        pool.spot && !contains([for t in pool.taints : t.key], "cloud.google.com/gke-spot")
        ? [
          {
            key    = "cloud.google.com/gke-spot"
            value  = "true"
            effect = "NO_SCHEDULE"
          }
        ]
        : []
      )
    }
  }

  all_node_pools = merge(local.system_pool, local.workload_pools)
}
