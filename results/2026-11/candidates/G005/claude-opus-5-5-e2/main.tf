locals {
  vpc_name    = "apps-${var.environment}"
  subnet_name = "${local.vpc_name}-gke-${var.region}"

  network    = "projects/${var.project_id}/global/networks/${local.vpc_name}"
  subnetwork = "projects/${var.project_id}/regions/${var.region}/subnetworks/${local.subnet_name}"

  release_channel = coalesce(var.release_channel, var.environment == "prod" ? "STABLE" : "REGULAR")

  labels = merge(var.labels, {
    environment = var.environment
    cluster     = var.name
    managed-by  = "opentofu"
  })

  # Minimal roles for nodes. Workloads must NOT use the node identity; they get
  # their own IAM bindings via Workload Identity Federation for GKE.
  node_sa_roles = [
    "roles/container.defaultNodeServiceAccount",
    "roles/artifactregistry.reader",
  ]
}

# ---------------------------------------------------------------------------
# Dedicated, least-privilege node service account
# ---------------------------------------------------------------------------
resource "google_service_account" "nodes" {
  project      = var.project_id
  account_id   = trimsuffix(substr("gke-${var.name}", 0, 30), "-")
  display_name = "GKE nodes for cluster ${var.name}"
}

resource "google_project_iam_member" "nodes" {
  for_each = toset(local.node_sa_roles)

  project = var.project_id
  role    = each.value
  member  = google_service_account.nodes.member
}

# ---------------------------------------------------------------------------
# Cluster
# ---------------------------------------------------------------------------
resource "google_container_cluster" "this" {
  project  = var.project_id
  name     = var.name
  location = var.region # regional: control plane and nodes replicated across zones

  network    = local.network
  subnetwork = local.subnetwork

  deletion_protection = var.deletion_protection

  # Node pools are managed separately below.
  remove_default_node_pool = true
  initial_node_count       = 1

  node_config {
    service_account = google_service_account.nodes.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]
    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }
    workload_metadata_config {
      mode = "GKE_METADATA"
    }
  }

  networking_mode = "VPC_NATIVE"
  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  # Dataplane V2: eBPF datapath with built-in Kubernetes NetworkPolicy enforcement.
  datapath_provider = "ADVANCED_DATAPATH"

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = length(var.master_authorized_networks) == 0
    master_ipv4_cidr_block  = var.master_ipv4_cidr_block
    master_global_access_config {
      enabled = true
    }
  }

  control_plane_endpoints_config {
    dns_endpoint_config {
      # IAM-authenticated endpoint usable from anywhere; no IP allow-listing needed.
      allow_external_traffic = true
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

  release_channel {
    channel = local.release_channel
  }

  maintenance_policy {
    recurring_window {
      start_time = var.maintenance_window.start_time
      end_time   = var.maintenance_window.end_time
      recurrence = var.maintenance_window.recurrence
    }
  }

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  enable_shielded_nodes = true
  enable_legacy_abac    = false

  master_auth {
    client_certificate_config {
      issue_client_certificate = false
    }
  }

  dynamic "database_encryption" {
    for_each = var.database_encryption_key == null ? [] : [var.database_encryption_key]
    content {
      state    = "ENCRYPTED"
      key_name = database_encryption.value
    }
  }

  security_posture_config {
    mode               = "BASIC"
    vulnerability_mode = "VULNERABILITY_BASIC"
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

  gateway_api_config {
    channel = "CHANNEL_STANDARD"
  }

  logging_config {
    enable_components = ["SYSTEM_COMPONENTS", "WORKLOADS", "APISERVER"]
  }

  monitoring_config {
    enable_components = ["SYSTEM_COMPONENTS", "APISERVER", "SCHEDULER", "CONTROLLER_MANAGER", "STORAGE", "POD", "DEPLOYMENT", "STATEFULSET", "DAEMONSET", "HPA"]
    managed_prometheus {
      enabled = true
    }
  }

  # Shared clusters: attribute cost per namespace / label.
  cost_management_config {
    enabled = true
  }

  resource_labels = local.labels

  lifecycle {
    ignore_changes = [node_config]
  }

  depends_on = [google_project_iam_member.nodes]
}

# ---------------------------------------------------------------------------
# Node pools
# ---------------------------------------------------------------------------
resource "google_container_node_pool" "pools" {
  for_each = var.node_pools

  project  = var.project_id
  name     = each.key
  location = var.region
  cluster  = google_container_cluster.this.name

  initial_node_count = each.value.min_node_count

  autoscaling {
    min_node_count  = each.value.min_node_count
    max_node_count  = each.value.max_node_count
    location_policy = each.value.spot ? "ANY" : "BALANCED"
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  upgrade_settings {
    strategy        = "SURGE"
    max_surge       = 1
    max_unavailable = 0
  }

  node_config {
    machine_type    = each.value.machine_type
    disk_size_gb    = each.value.disk_size_gb
    disk_type       = each.value.disk_type
    image_type      = "COS_CONTAINERD"
    spot            = each.value.spot
    service_account = google_service_account.nodes.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]

    labels          = merge(each.value.labels, { "node-pool" = each.key })
    resource_labels = local.labels

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
    ignore_changes = [initial_node_count]
  }
}
