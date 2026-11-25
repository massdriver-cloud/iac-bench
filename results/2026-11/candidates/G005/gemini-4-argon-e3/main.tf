locals {
  vpc_name    = "apps-${var.environment}"
  subnet_name = "${local.vpc_name}-gke-${var.region}"

  pods_range_name     = "pods"
  services_range_name = "services"

  common_labels = merge(
    {
      environment = var.environment
      cluster     = var.cluster_name
      managed_by  = "opentofu"
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

# Least-privilege dedicated service account for GKE nodes
resource "google_service_account" "cluster_nodes" {
  project      = var.project_id
  account_id   = substr("gke-${var.cluster_name}-nodes", 0, 30)
  display_name = "GKE nodes SA for ${var.cluster_name}"
  description  = "Least-privilege node service account for GKE cluster ${var.cluster_name}"
}

resource "google_project_iam_member" "cluster_nodes" {
  for_each = local.node_sa_roles

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.cluster_nodes.email}"
}

# Regional GKE Standard Cluster
resource "google_container_cluster" "primary" {
  project  = var.project_id
  name     = var.cluster_name
  location = var.region

  network    = "projects/${var.project_id}/global/networks/${local.vpc_name}"
  subnetwork = "projects/${var.project_id}/regions/${var.region}/subnetworks/${local.subnet_name}"

  # Manage node pools separately via google_container_node_pool to prevent cluster recreation on node changes
  remove_default_node_pool = true
  initial_node_count       = 1

  networking_mode = "VPC_NATIVE"

  ip_allocation_policy {
    cluster_secondary_range_name  = local.pods_range_name
    services_secondary_range_name = local.services_range_name
  }

  # Private nodes with private control plane
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = var.enable_private_endpoint
    master_ipv4_cidr_block  = var.master_ipv4_cidr_block

    master_global_access_config {
      enabled = true
    }
  }

  dynamic "master_authorized_networks_config" {
    for_each = length(var.master_authorized_networks) > 0 || var.enable_private_endpoint ? [1] : []
    content {
      dynamic "cidr_blocks" {
        for_each = var.master_authorized_networks
        content {
          cidr_block   = cidr_blocks.value.cidr_block
          display_name = cidr_blocks.value.display_name
        }
      }
    }
  }

  # Workload Identity Federation for GKE so Pods authenticate cleanly to Pub/Sub, Cloud Storage, Cloud SQL, etc.
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  # Dataplane V2 (eBPF / Cilium) provides built-in NetworkPolicy enforcement and Pod-level network visibility
  datapath_provider = "ADVANCED_DATAPATH"

  release_channel {
    channel = var.release_channel
  }

  maintenance_policy {
    daily_maintenance_window {
      start_time = var.maintenance_start_time
    }
  }

  # Security posture and hardening
  enable_shielded_nodes = true

  binary_authorization {
    evaluation_mode = "PROJECT_SINGLETON_POLICY_ENFORCE"
  }

  security_posture_config {
    mode               = "BASIC"
    vulnerability_mode = "VULNERABILITY_BASIC"
  }

  # Multi-tenant cost tracking and observability
  cost_management_config {
    enabled = true
  }

  logging_config {
    enable_components = [
      "SYSTEM_COMPONENTS",
      "WORKLOADS",
    ]
  }

  monitoring_config {
    enable_components = [
      "SYSTEM_COMPONENTS",
      "APISERVER",
      "SCHEDULER",
      "CONTROLLER_MANAGER",
    ]

    managed_prometheus {
      enabled = true
    }
  }

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
    gcp_filestore_csi_driver_config {
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

  resource_labels     = local.common_labels
  deletion_protection = var.deletion_protection

  lifecycle {
    ignore_changes = [
      initial_node_count,
    ]
  }
}

# Managed Node Pools
resource "google_container_node_pool" "pools" {
  for_each = var.node_pools

  project  = var.project_id
  name     = each.key
  location = var.region
  cluster  = google_container_cluster.primary.name

  initial_node_count = each.value.min_node_count
  node_locations     = each.value.node_locations

  autoscaling {
    min_node_count  = each.value.min_node_count
    max_node_count  = each.value.max_node_count
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
    machine_type    = each.value.machine_type
    disk_size_gb    = each.value.disk_size_gb
    disk_type       = each.value.disk_type
    image_type      = each.value.image_type
    spot            = each.value.spot
    service_account = google_service_account.cluster_nodes.email

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform",
    ]

    # Enforce Workload Identity metadata server on all nodes (prevents pods from using node SA credentials)
    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    metadata = {
      disable-legacy-endpoints = "true"
    }

    labels = merge(
      local.common_labels,
      {
        node_pool = each.key
      },
      each.value.labels
    )

    tags = distinct(concat(
      [
        "gke-${var.cluster_name}",
        "gke-${var.cluster_name}-${each.key}",
      ],
      each.value.tags
    ))

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
    ignore_changes = [
      initial_node_count,
    ]
  }
}
