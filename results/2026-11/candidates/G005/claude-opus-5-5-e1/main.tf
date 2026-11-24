locals {
  network_name    = "apps-${var.environment}"
  subnetwork_name = "${local.network_name}-gke-${var.region}"
  network_id      = "projects/${var.project_id}/global/networks/${local.network_name}"
  subnetwork_id   = "projects/${var.project_id}/regions/${var.region}/subnetworks/${local.subnetwork_name}"
  workload_pool   = "${var.project_id}.svc.id.goog"

  # SA IDs are max 30 chars and must not end with a hyphen.
  node_sa_id = replace(substr("gke-${var.name}-nodes", 0, 30), "/-+$/", "")

  labels = merge(var.labels, {
    cluster     = var.name
    environment = var.environment
    managed-by  = "opentofu"
  })

  # Minimal roles a GKE node needs (logging, monitoring, pulling images).
  # Workloads must NOT use the node identity: they get their own IAM via Workload Identity.
  node_sa_roles = toset([
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/monitoring.viewer",
    "roles/stackdriver.resourceMetadata.writer",
    "roles/autoscaling.metricsWriter",
    "roles/artifactregistry.reader",
  ])
}

resource "google_project_service" "container" {
  project            = var.project_id
  service            = "container.googleapis.com"
  disable_on_destroy = false
}

# Dedicated, least-privilege node service account (instead of the Compute default SA).
resource "google_service_account" "nodes" {
  project      = var.project_id
  account_id   = local.node_sa_id
  display_name = "GKE nodes for cluster ${var.name}"
}

resource "google_project_iam_member" "nodes" {
  for_each = local.node_sa_roles

  project = var.project_id
  role    = each.value
  member  = google_service_account.nodes.member
}

resource "google_container_cluster" "this" {
  project  = var.project_id
  name     = var.name
  location = var.region # regional: control plane and nodes replicated across zones

  deletion_protection = var.deletion_protection

  network    = local.network_id
  subnetwork = local.subnetwork_id

  networking_mode = "VPC_NATIVE"
  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  # Dataplane V2 (eBPF) – also enforces Kubernetes NetworkPolicy for multi-tenant isolation.
  datapath_provider = "ADVANCED_DATAPATH"

  # Node pools are managed separately.
  remove_default_node_pool = true
  initial_node_count       = 1

  release_channel {
    channel = var.release_channel
  }

  # Nodes get no public IPs. The control plane keeps a public endpoint, but it is
  # locked down to master_authorized_networks (empty = only reachable from the VPC).
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
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

  # Workloads reach Pub/Sub, Cloud Storage, Cloud SQL... with per-KSA identities.
  workload_identity_config {
    workload_pool = local.workload_pool
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

  gateway_api_config {
    channel = "CHANNEL_STANDARD"
  }

  vertical_pod_autoscaling {
    enabled = true
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

  maintenance_policy {
    recurring_window {
      start_time = var.maintenance_window.start_time
      end_time   = var.maintenance_window.end_time
      recurrence = var.maintenance_window.recurrence
    }
  }

  cost_management_config {
    enabled = true
  }

  resource_labels = local.labels

  # Applied only to the temporary default pool that is removed right away.
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

  depends_on = [
    google_project_service.container,
    google_project_iam_member.nodes,
  ]
}

resource "google_container_node_pool" "pools" {
  for_each = var.node_pools

  project  = var.project_id
  name     = each.key
  location = var.region
  cluster  = google_container_cluster.this.name

  node_locations     = each.value.node_locations
  initial_node_count = each.value.initial_node_count

  autoscaling {
    min_node_count  = each.value.min_node_count
    max_node_count  = each.value.max_node_count
    location_policy = each.value.spot ? "ANY" : "BALANCED"
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  # Add a node before draining one: no capacity loss during upgrades.
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
    # Access is governed by IAM on the node SA; scopes are left broad as Google recommends.
    oauth_scopes = ["https://www.googleapis.com/auth/cloud-platform"]

    labels          = merge(each.value.labels, { "node-pool" = each.key })
    resource_labels = local.labels

    dynamic "taint" {
      for_each = each.value.taints
      content {
        key    = taint.value.key
        value  = taint.value.value
        effect = taint.value.effect
      }
    }

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
  }

  lifecycle {
    ignore_changes = [initial_node_count]
  }
}
