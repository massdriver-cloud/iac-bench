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

  # Least-privilege roles for the node service account. Workloads must NOT use
  # this identity; they use Workload Identity with their own service accounts.
  node_sa_roles = [
    "roles/container.defaultNodeServiceAccount",
    "roles/artifactregistry.reader",
  ]
}

# Dedicated, minimally-privileged service account for nodes (instead of the
# Compute Engine default SA, which has Editor).
resource "google_service_account" "nodes" {
  project      = var.project_id
  account_id   = "gke-${var.name}"
  display_name = "GKE nodes for cluster ${var.name} (${var.environment})"
}

resource "google_project_iam_member" "nodes" {
  for_each = toset(local.node_sa_roles)

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.nodes.email}"
}

resource "google_container_cluster" "this" {
  provider = google

  project  = var.project_id
  name     = var.name
  location = var.region # regional: control plane and nodes replicated across zones

  network    = local.network
  subnetwork = local.subnetwork

  deletion_protection = var.deletion_protection

  # Node pools are managed separately; the default pool is removed.
  remove_default_node_pool = true
  initial_node_count       = 1

  resource_labels = local.labels

  networking_mode   = "VPC_NATIVE"
  datapath_provider = "ADVANCED_DATAPATH" # Dataplane V2: built-in NetworkPolicy enforcement

  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = true
  }

  control_plane_endpoints_config {
    dns_endpoint_config {
      # IAM-authenticated DNS endpoint for kubectl/CI from outside the VPC.
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

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  enable_shielded_nodes       = true
  enable_intranode_visibility = true

  binary_authorization {
    evaluation_mode = "PROJECT_SINGLETON_POLICY_ENFORCE"
  }

  security_posture_config {
    mode               = "BASIC"
    vulnerability_mode = "VULNERABILITY_BASIC"
  }

  dynamic "database_encryption" {
    for_each = var.database_encryption_kms_key == null ? [] : [var.database_encryption_kms_key]
    content {
      state    = "ENCRYPTED"
      key_name = database_encryption.value
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
    gcs_fuse_csi_driver_config {
      enabled = true
    }
    dns_cache_config {
      enabled = true
    }
  }

  gateway_api_config {
    channel = "CHANNEL_STANDARD"
  }

  vertical_pod_autoscaling {
    enabled = true
  }

  cluster_autoscaling {
    autoscaling_profile = "BALANCED"
  }

  logging_config {
    enable_components = ["SYSTEM_COMPONENTS", "WORKLOADS"]
  }

  monitoring_config {
    enable_components = ["SYSTEM_COMPONENTS"]
    managed_prometheus {
      enabled = true
    }
  }

  cost_management_config {
    enabled = true
  }

  maintenance_policy {
    recurring_window {
      start_time = var.maintenance_window.start_time
      end_time   = var.maintenance_window.end_time
      recurrence = var.maintenance_window.recurrence
    }
  }

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

  lifecycle {
    ignore_changes = [node_config, initial_node_count]
  }

  depends_on = [google_project_iam_member.nodes]
}

resource "google_container_node_pool" "pools" {
  for_each = var.node_pools

  project  = var.project_id
  name     = each.key
  location = var.region
  cluster  = google_container_cluster.this.name

  autoscaling {
    min_node_count  = each.value.min_nodes_per_zone
    max_node_count  = each.value.max_nodes_per_zone
    location_policy = each.value.spot ? "ANY" : "BALANCED"
  }

  initial_node_count = max(each.value.min_nodes_per_zone, 1)

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

    resource_labels = local.labels
    labels          = merge(each.value.labels, { "node-pool" = each.key })

    metadata = {
      disable-legacy-endpoints = "true"
    }

    dynamic "taint" {
      for_each = each.value.taints
      content {
        key    = taint.value.key
        value  = taint.value.value
        effect = taint.value.effect
      }
    }

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    workload_metadata_config {
      mode = "GKE_METADATA"
    }
  }

  lifecycle {
    ignore_changes = [initial_node_count]
  }
}
