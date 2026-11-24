locals {
  vpc_name    = "apps-${var.environment}"
  subnet_name = "${local.vpc_name}-gke-${var.region}"

  network_self_link    = "projects/${var.project_id}/global/networks/${local.vpc_name}"
  subnetwork_self_link = "projects/${var.project_id}/regions/${var.region}/subnetworks/${local.subnet_name}"

  # Secondary ranges are created by the network team with fixed names.
  pods_range_name     = "pods"
  services_range_name = "services"

  labels = merge(
    var.labels,
    {
      environment = var.environment
      managed-by  = "opentofu"
    },
  )

  # Recurring maintenance window: the date only anchors the first occurrence; recurrence does the rest.
  maintenance_start = "2024-01-01T${var.maintenance_window.start_time}:00Z"
  maintenance_end   = "2024-01-01T${var.maintenance_window.end_time}:00Z"
  maintenance_rrule = "FREQ=WEEKLY;BYDAY=${join(",", var.maintenance_window.days)}"

  # Service account IDs are capped at 30 chars; cluster names can be 40. Fall back to a
  # truncated name plus a stable hash so the ID stays unique and never changes afterwards.
  node_sa_id_plain = "gke-${var.cluster_name}-nodes"
  node_sa_id = (
    length(local.node_sa_id_plain) <= 30
    ? local.node_sa_id_plain
    : "gke-${substr(var.cluster_name, 0, 13)}-${substr(md5(var.cluster_name), 0, 6)}-nodes"
  )

  # Least privilege for nodes: write logs/metrics, pull images. Workloads get their own identities
  # via Workload Identity - nothing else is granted to the node identity.
  node_sa_roles = [
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/monitoring.viewer",
    "roles/stackdriver.resourceMetadata.writer",
    "roles/autoscaling.metricsWriter",
    "roles/artifactregistry.reader",
  ]
}

########################################
# Node service account
########################################

resource "google_service_account" "nodes" {
  project      = var.project_id
  account_id   = local.node_sa_id
  display_name = "GKE nodes for cluster ${var.cluster_name} (${var.region})"
  description  = "Least-privilege identity for GKE node VMs. Managed by OpenTofu."
}

resource "google_project_iam_member" "nodes" {
  for_each = toset(local.node_sa_roles)

  project = var.project_id
  role    = each.value
  member  = google_service_account.nodes.member
}

########################################
# Cluster
########################################

resource "google_container_cluster" "this" {
  project  = var.project_id
  name     = var.cluster_name
  location = var.region # regional: HA control plane, nodes spread over the region's zones

  description         = "GKE Standard cluster (${var.environment}) managed by OpenTofu."
  deletion_protection = var.deletion_protection
  resource_labels     = local.labels

  # Node pools are managed as separate resources; the default pool is created and removed immediately.
  remove_default_node_pool = true
  initial_node_count       = 1

  # Make the short-lived default pool as safe as the managed ones (no default compute SA).
  node_config {
    service_account = google_service_account.nodes.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]
    image_type      = "COS_CONTAINERD"

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    workload_metadata_config {
      mode = "GKE_METADATA"
    }
  }

  # --- Networking: VPC-native on the network team's subnet, Dataplane V2 ---
  network           = local.network_self_link
  subnetwork        = local.subnetwork_self_link
  networking_mode   = "VPC_NATIVE"
  datapath_provider = "ADVANCED_DATAPATH" # Dataplane V2: eBPF networking, NetworkPolicy enforcement built in

  ip_allocation_policy {
    cluster_secondary_range_name  = local.pods_range_name
    services_secondary_range_name = local.services_range_name
  }

  default_max_pods_per_node = 110
  enable_l4_ilb_subsetting  = true

  dns_config {
    cluster_dns        = "CLOUD_DNS"
    cluster_dns_scope  = "CLUSTER_SCOPE"
    cluster_dns_domain = "cluster.local"
  }

  gateway_api_config {
    channel = "CHANNEL_STANDARD"
  }

  # --- Control plane access: private nodes, restricted API endpoint ---
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = var.enable_private_endpoint
    master_ipv4_cidr_block  = var.master_ipv4_cidr_block

    master_global_access_config {
      enabled = true
    }
  }

  master_authorized_networks_config {
    gcp_public_cidrs_access_enabled = false

    dynamic "cidr_blocks" {
      for_each = var.master_authorized_networks
      content {
        cidr_block   = cidr_blocks.value.cidr_block
        display_name = cidr_blocks.value.display_name
      }
    }
  }

  master_auth {
    client_certificate_config {
      issue_client_certificate = false
    }
  }

  enable_legacy_abac = false

  # --- Identity & security ---
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  enable_shielded_nodes = true

  security_posture_config {
    mode               = "BASIC"
    vulnerability_mode = "VULNERABILITY_BASIC"
  }

  binary_authorization {
    evaluation_mode = var.enable_binary_authorization ? "PROJECT_SINGLETON_POLICY_ENFORCE" : "DISABLED"
  }

  dynamic "database_encryption" {
    for_each = var.database_encryption_key == null ? [] : [var.database_encryption_key]
    content {
      state    = "ENCRYPTED"
      key_name = database_encryption.value
    }
  }

  # --- Upgrades & maintenance ---
  release_channel {
    channel = var.release_channel
  }

  maintenance_policy {
    recurring_window {
      start_time = local.maintenance_start
      end_time   = local.maintenance_end
      recurrence = local.maintenance_rrule
    }
  }

  # --- Observability ---
  logging_config {
    enable_components = ["SYSTEM_COMPONENTS", "WORKLOADS"]
  }

  monitoring_config {
    enable_components = ["SYSTEM_COMPONENTS", "DEPLOYMENT", "STATEFULSET", "DAEMONSET", "HPA", "POD"]

    managed_prometheus {
      enabled = true
    }
  }

  # --- Add-ons ---
  addons_config {
    http_load_balancing {
      disabled = false
    }
    horizontal_pod_autoscaling {
      disabled = false
    }
    gce_persistent_disk_csi_driver_config {
      enabled = true
    }
    gcs_fuse_csi_driver_config {
      enabled = true
    }
    dns_cache_config {
      enabled = true
    }
  }

  vertical_pod_autoscaling {
    enabled = true
  }

  cost_management_config {
    enabled = true
  }

  lifecycle {
    # node_config only matters for the removed default pool; real pools live in google_container_node_pool.
    ignore_changes = [node_config, initial_node_count]
  }

  timeouts {
    create = "45m"
    update = "45m"
    delete = "45m"
  }

  depends_on = [google_project_iam_member.nodes]
}

########################################
# Node pools
########################################

resource "google_container_node_pool" "this" {
  for_each = var.node_pools

  project  = var.project_id
  cluster  = google_container_cluster.this.id
  location = var.region

  # name_prefix + create_before_destroy: changes that force a new pool (machine type, disk, ...)
  # bring the replacement up before the old pool drains, so workloads stay scheduled.
  name_prefix    = "${each.key}-"
  node_locations = each.value.node_locations

  initial_node_count = each.value.min_nodes
  max_pods_per_node  = each.value.max_pods_per_node

  autoscaling {
    min_node_count  = each.value.min_nodes
    max_node_count  = each.value.max_nodes
    location_policy = "BALANCED"
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  upgrade_settings {
    strategy        = "SURGE"
    max_surge       = each.value.max_surge
    max_unavailable = each.value.max_unavailable
  }

  node_config {
    machine_type = each.value.machine_type
    disk_size_gb = each.value.disk_size_gb
    disk_type    = each.value.disk_type
    image_type   = each.value.image_type
    spot         = each.value.spot

    service_account = google_service_account.nodes.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]

    labels = merge(each.value.labels, { "node-pool" = each.key })
    tags   = each.value.tags
    resource_labels = merge(local.labels, {
      cluster   = var.cluster_name
      node-pool = each.key
    })

    metadata = {
      disable-legacy-endpoints = "true"
    }

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    dynamic "taint" {
      for_each = each.value.taints
      content {
        key    = taint.value.key
        value  = taint.value.value
        effect = taint.value.effect
      }
    }
  }

  lifecycle {
    create_before_destroy = true
    # The autoscaler owns the live node count after creation.
    ignore_changes = [initial_node_count]
  }

  timeouts {
    create = "45m"
    update = "45m"
    delete = "45m"
  }
}
