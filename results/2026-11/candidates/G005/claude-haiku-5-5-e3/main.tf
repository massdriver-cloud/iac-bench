locals {
  # Network team naming convention.
  network_name    = "apps-${var.environment}"
  subnetwork_name = "${local.network_name}-gke-${var.region}"

  # Secondary range names the network team created on every GKE subnet.
  pods_range_name     = "pods"
  services_range_name = "services"

  common_labels = merge(var.labels, {
    environment = var.environment
    managed-by  = "opentofu"
  })

  # Service account IDs are capped at 30 characters.
  node_sa_account_id = trimsuffix(substr("${var.name}-nodes", 0, 30), "-")

  # Roles the nodes need for logging, metrics and pulling images. Workloads get
  # their own permissions through Workload Identity, not through the node account.
  node_sa_roles = [
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/monitoring.viewer",
    "roles/stackdriver.resourceMetadata.writer",
    "roles/artifactregistry.reader",
  ]
}

# The network team's GKE subnet. Looked up, never created, by this module.
data "google_compute_subnetwork" "gke" {
  name    = local.subnetwork_name
  region  = var.region
  project = var.project_id

  lifecycle {
    postcondition {
      condition = alltrue([
        for r in [local.pods_range_name, local.services_range_name] :
        contains([for s in self.secondary_ip_range : s.range_name], r)
      ])
      error_message = "Subnet ${local.subnetwork_name} must have secondary ranges named \"pods\" and \"services\"."
    }
  }
}

# Dedicated identity for node VMs. Keeps the default Compute Engine account out of the nodes.
resource "google_service_account" "nodes" {
  project      = var.project_id
  account_id   = local.node_sa_account_id
  display_name = "GKE nodes for ${var.name}"
}

resource "google_project_iam_member" "node_sa" {
  for_each = toset(local.node_sa_roles)

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.nodes.email}"
}

resource "google_container_cluster" "this" {
  name     = var.name
  project  = var.project_id
  location = var.region

  deletion_protection = var.deletion_protection

  network    = data.google_compute_subnetwork.gke.network
  subnetwork = data.google_compute_subnetwork.gke.id

  # Node pools are managed as separate resources so each can be sized and upgraded independently.
  remove_default_node_pool = true
  initial_node_count       = 1

  ip_allocation_policy {
    cluster_secondary_range_name  = local.pods_range_name
    services_secondary_range_name = local.services_range_name
  }

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = var.enable_private_endpoint
    master_ipv4_cidr_block  = var.master_ipv4_cidr_block

    master_global_access_config {
      enabled = false
    }
  }

  master_authorized_networks_config {
    dynamic "cidr_blocks" {
      for_each = var.master_authorized_networks
      content {
        cidr_block   = cidr_blocks.value.cidr_block
        display_name = cidr_blocks.value.display_name
      }
    }
  }

  release_channel {
    channel = var.release_channel
  }

  maintenance_policy {
    recurring_window {
      start_time = var.maintenance_window.start_time
      end_time   = var.maintenance_window.end_time
      recurrence = var.maintenance_window.recurrence
    }
  }

  # Dataplane V2 (eBPF) provides Kubernetes NetworkPolicy enforcement, so no separate network policy add-on is set.
  datapath_provider = "ADVANCED_DATAPATH"

  enable_shielded_nodes = true

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
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
  }

  gateway_api_config {
    channel = "CHANNEL_STANDARD"
  }

  master_auth {
    client_certificate_config {
      issue_client_certificate = false
    }
  }

  node_pool_defaults {
    node_config_defaults {
      insecure_kubelet_readonly_port_enabled = "FALSE"
    }
  }

  database_encryption {
    state    = var.kms_key_id == null ? "DECRYPTED" : "ENCRYPTED"
    key_name = var.kms_key_id
  }

  binary_authorization {
    evaluation_mode = var.binary_authorization_evaluation_mode
  }

  security_posture_config {
    mode               = "BASIC"
    vulnerability_mode = "VULNERABILITY_BASIC"
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

  resource_labels = local.common_labels

  lifecycle {
    precondition {
      condition     = var.environment != "prod" || var.kms_key_id != null
      error_message = "kms_key_id is required for prod clusters so Kubernetes Secrets are encrypted with a customer-managed key."
    }
    precondition {
      condition     = var.environment != "prod" || var.deletion_protection
      error_message = "deletion_protection must stay enabled for prod clusters."
    }
    precondition {
      condition     = var.environment != "prod" || var.release_channel != "RAPID"
      error_message = "Prod clusters must not use the RAPID release channel."
    }
    ignore_changes = [
      initial_node_count,
    ]
  }
}

resource "google_container_node_pool" "this" {
  for_each = var.node_pools

  name     = each.key
  project  = var.project_id
  location = var.region
  cluster  = google_container_cluster.this.name

  node_locations = each.value.node_locations

  autoscaling {
    # Per zone in a regional cluster.
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
    machine_type = each.value.machine_type
    disk_size_gb = each.value.disk_size_gb
    disk_type    = each.value.disk_type
    image_type   = each.value.image_type

    service_account = google_service_account.nodes.email
    # Access is controlled by IAM on the node service account and by Workload Identity, not by legacy node scopes.
    oauth_scopes = ["https://www.googleapis.com/auth/cloud-platform"]

    labels = merge(local.common_labels, each.value.node_labels)

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
    precondition {
      condition = each.value.node_locations == null ? true : alltrue([
        for z in each.value.node_locations : startswith(z, var.region)
      ])
      error_message = "Every node_locations entry for pool ${each.key} must be a zone in ${var.region}."
    }
  }
}
