# ===========================================================================
# Locals
# ===========================================================================

locals {
  # The network team's subnet naming convention: <vpc>-gke-<region>.
  subnet_name = var.subnet_name != null ? var.subnet_name : "${var.vpc_name}-gke-${var.region}"

  # Kubernetes taint effect spelling -> GKE API spelling.
  taint_effects = {
    NoSchedule       = "NO_SCHEDULE"
    PreferNoSchedule = "PREFER_NO_SCHEDULE"
    NoExecute        = "NO_EXECUTE"
  }

  # A small, always-present pool for GKE and Kubernetes system components
  # (kube-dns, metrics agents, ...). Counts are per zone, so the default keeps
  # at least one system node alive in each of the region's zones.
  system_node_pool = {
    machine_type = "e2-standard-4"
    min_count    = 1
    max_count    = 3
    disk_size_gb = 100
    disk_type    = "pd-balanced"
    spot         = false
    labels = {
      purpose = "system"
    }
    taints = []
  }

  # Product-team pools are merged on top of the system pool; an entry keyed
  # "system" replaces the module default.
  node_pools = merge({ system = local.system_node_pool }, var.node_pools)
}

# ===========================================================================
# Cluster
# ===========================================================================

resource "google_container_cluster" "this" {
  provider = google

  name     = var.name
  location = var.region # regional: control plane and nodes across all zones

  # --- Networking ---------------------------------------------------------
  # Clusters run Dataplane V2 (the GKE default for new clusters on supported
  # versions), which enforces NetworkPolicy without a Calico DaemonSet and
  # gives better service-visibility.
  network    = var.vpc_name
  subnetwork = local.subnet_name

  ip_allocation_policy {
    cluster_secondary_range_name  = var.pods_secondary_range_name
    services_secondary_range_name = var.services_secondary_range_name
    stack_type                    = "IPV4"
  }

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = var.enable_private_endpoint
    master_ipv4_cidr_block  = var.master_ipv4_cidr_block

    # Lets operators reach the control plane's private endpoint from VPC
    # subnets in other regions (e.g. a VPN concentrator outside the region).
    master_global_access_config {
      enabled = true
    }
  }

  release_channel {
    channel = var.release_channel
  }

  remove_default_node_pool = true
  initial_node_count       = 1 # placeholder node used only to create the cluster
  deletion_protection      = var.deletion_protection

  default_max_pods_per_node = var.default_max_pods_per_node

  maintenance_policy {
    recurring_window {
      start_time = format("2024-01-01T%s:00Z", var.maintenance_window.start)
      end_time   = format("2024-01-01T%s:00Z", var.maintenance_window.end)
      recurrence = var.maintenance_window.recurrence
    }
  }

  # --- Security -----------------------------------------------------------
  enable_shielded_nodes = true

  # Only set when there is something to allow-list; when the endpoint is
  # private this block is simply omitted.
  dynamic "master_authorized_networks_config" {
    for_each = length(var.master_authorized_networks) > 0 ? toset(["enabled"]) : toset([])
    content {
      dynamic "cidr_blocks" {
        for_each = var.master_authorized_networks
        content {
          cidr_block   = cidr_blocks.value
          display_name = cidr_blocks.key
        }
      }
    }
  }

  enable_l4_ilb_subsetting = true

  # Block Services of type ExternalIP: a hardening measure that stops any
  # team from bypassing the load balancer with arbitrary node IPs.
  service_external_ips_config {
    enabled = false
  }

  # Workload Identity: pods authenticate as Kubernetes service accounts
  # instead of sharing the node service account's credentials.
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  # Optional CMEK for Kubernetes Secrets.
  dynamic "database_encryption" {
    for_each = var.database_encryption_key != null ? toset(["enabled"]) : toset([])
    content {
      state    = "ENCRYPTED"
      key_name = var.database_encryption_key
    }
  }

  # Optional Binary Authorization: enforce the project's policy so only
  # admitted (e.g. signed) images can run.
  dynamic "binary_authorization" {
    for_each = var.enable_binary_authorization ? toset(["enabled"]) : toset([])
    content {
      evaluation_mode = "PROJECT_SINGLETON_POLICY_ENFORCE"
    }
  }

  dynamic "gateway_api_config" {
    for_each = var.enable_gateway_api ? toset(["enabled"]) : toset([])
    content {
      channel = "CHANNEL_STANDARD"
    }
  }

  # --- Observability ------------------------------------------------------
  logging_config {
    enable_components = [
      "SYSTEM_COMPONENTS",
      "WORKLOADS",
    ]
  }

  monitoring_config {
    enable_components = [
      "SYSTEM_COMPONENTS",
      "DEPLOYMENT",
      "STATEFULSET",
      "DAEMONSET",
      "HPA",
      "POD",
      "CADVISOR",
    ]
  }

  resource_labels = var.resource_labels

  lifecycle {
    precondition {
      condition     = var.enable_private_endpoint || length(var.master_authorized_networks) > 0
      error_message = "A public control-plane endpoint must be allow-listed: keep enable_private_endpoint = true, or provide at least one entry in master_authorized_networks."
    }
  }
}
