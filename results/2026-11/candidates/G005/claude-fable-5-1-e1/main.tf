locals {
  vpc_name    = "apps-${var.environment}"
  subnet_name = "${local.vpc_name}-gke-${var.region}"

  network_self_link    = "projects/${var.project_id}/global/networks/${local.vpc_name}"
  subnetwork_self_link = "projects/${var.project_id}/regions/${var.region}/subnetworks/${local.subnet_name}"

  pods_range_name     = "pods"
  services_range_name = "services"

  # Network tag carried by every node of this cluster; used to scope firewall rules.
  node_tag = "gke-${var.cluster_name}"

  # Service account ids are limited to 30 characters; prefix with "gke-" and trim cleanly.
  node_sa_account_id = trimsuffix(substr("gke-${var.cluster_name}", 0, 30), "-")

  common_labels = merge(var.labels, {
    environment = var.environment
    cluster     = var.cluster_name
    managed-by  = "opentofu"
  })

  # Least-privilege roles for the node service account: ship logs/metrics and pull images.
  node_sa_roles = [
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/monitoring.viewer",
    "roles/stackdriver.resourceMetadata.writer",
    "roles/artifactregistry.reader",
  ]
}

############################################
# Node service account (no default compute SA)
############################################

resource "google_service_account" "nodes" {
  project      = var.project_id
  account_id   = local.node_sa_account_id
  display_name = "GKE nodes for cluster ${var.cluster_name}"
  description  = "Least-privilege identity for GKE node VMs. Workloads use Workload Identity, not this account."
}

resource "google_project_iam_member" "nodes" {
  for_each = toset(local.node_sa_roles)

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.nodes.email}"
}

############################################
# Cluster
############################################

resource "google_container_cluster" "this" {
  project  = var.project_id
  name     = var.cluster_name
  location = var.region # regional: control plane and nodes replicated across zones

  network    = local.network_self_link
  subnetwork = local.subnetwork_self_link

  deletion_protection = var.deletion_protection
  resource_labels     = local.common_labels

  # The module manages node pools as separate resources.
  remove_default_node_pool = true
  initial_node_count       = 1

  release_channel {
    channel = var.release_channel
  }

  # --- Networking -----------------------------------------------------------
  networking_mode   = "VPC_NATIVE"
  datapath_provider = "ADVANCED_DATAPATH" # Dataplane V2: eBPF, NetworkPolicy enforced natively

  ip_allocation_policy {
    cluster_secondary_range_name  = local.pods_range_name
    services_secondary_range_name = local.services_range_name
  }

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

  gateway_api_config {
    channel = "CHANNEL_STANDARD"
  }

  # --- Security -------------------------------------------------------------
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

  binary_authorization {
    evaluation_mode = var.enable_binary_authorization ? "PROJECT_SINGLETON_POLICY_ENFORCE" : "DISABLED"
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

  # --- Operations -----------------------------------------------------------
  maintenance_policy {
    recurring_window {
      start_time = var.maintenance_window.start_time
      end_time   = var.maintenance_window.end_time
      recurrence = var.maintenance_window.recurrence
    }
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

  vertical_pod_autoscaling {
    enabled = true
  }

  cost_management_config {
    enabled = true # per-namespace cost allocation for the teams sharing the cluster
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

  # Settings for the short-lived default pool that GKE creates before we remove it,
  # so that it never runs with the default compute service account.
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

############################################
# Node pools
############################################

resource "google_container_node_pool" "this" {
  for_each = var.node_pools

  project  = var.project_id
  name     = each.key
  cluster  = google_container_cluster.this.id
  location = var.region

  node_locations = each.value.node_locations

  autoscaling {
    min_node_count  = each.value.min_nodes_per_zone
    max_node_count  = each.value.max_nodes_per_zone
    location_policy = each.value.spot ? "ANY" : "BALANCED"
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

    labels = merge(local.common_labels, each.value.labels, {
      node-pool = each.key
    })
    tags = distinct(concat([local.node_tag], each.value.tags))

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
  }
}

############################################
# Control plane -> node webhook ports
############################################

resource "google_compute_firewall" "control_plane_webhooks" {
  count = var.master_ipv4_cidr_block != null && length(var.control_plane_webhook_ports) > 0 ? 1 : 0

  project     = var.project_id
  name        = "gke-${var.cluster_name}-control-plane-webhooks"
  network     = local.network_self_link
  description = "Allow the GKE control plane of ${var.cluster_name} to reach admission webhooks on non-default ports."
  direction   = "INGRESS"

  source_ranges = [var.master_ipv4_cidr_block]
  target_tags   = [local.node_tag]

  allow {
    protocol = "tcp"
    ports    = var.control_plane_webhook_ports
  }
}
