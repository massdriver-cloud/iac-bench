locals {
  network_name = "apps-${var.environment}"
  subnet_name  = "${local.network_name}-gke-${var.region}"
  zones        = slice(sort(data.google_compute_zones.available.names), 0, min(3, length(data.google_compute_zones.available.names)))
  apis = toset([
    "compute.googleapis.com",
    "container.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "sts.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "artifactregistry.googleapis.com",
  ])
  workload_roles = {
    for item in flatten([
      for key, identity in var.workload_identities : [
        for role in identity.project_roles : { key = key, role = role }
      ]
    ]) : "${item.key}/${item.role}" => item
  }
}

resource "google_project_service" "required" {
  for_each           = local.apis
  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

data "google_compute_zones" "available" {
  project    = var.project_id
  region     = var.region
  status     = "UP"
  depends_on = [google_project_service.required]
}

# Read, never create or modify, network-team-owned infrastructure.
data "google_compute_network" "existing" {
  project    = var.project_id
  name       = local.network_name
  depends_on = [google_project_service.required]
}

data "google_compute_subnetwork" "existing" {
  project    = var.project_id
  region     = var.region
  name       = local.subnet_name
  depends_on = [google_project_service.required]
}

resource "google_service_account" "nodes" {
  project      = var.project_id
  account_id   = "gke-nodes-${substr(sha256("${var.region}/${var.cluster_name}"), 0, 16)}"
  display_name = "GKE ${var.cluster_name} nodes"
  depends_on   = [google_project_service.required]
}

resource "google_project_iam_member" "nodes" {
  for_each = toset([
    "roles/container.defaultNodeServiceAccount",
    "roles/artifactregistry.reader",
  ])
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.nodes.email}"
}

resource "google_container_cluster" "this" {
  project             = var.project_id
  name                = var.cluster_name
  location            = var.region
  node_locations      = local.zones
  deletion_protection = var.deletion_protection

  # Omitting enable_autopilot creates a Standard cluster.
  network    = data.google_compute_network.existing.self_link
  subnetwork = data.google_compute_subnetwork.existing.self_link

  # GKE requires an initial pool; delete it and manage all durable pools below.
  remove_default_node_pool = true
  initial_node_count       = 1
  node_config {
    service_account = google_service_account.nodes.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]
    metadata = {
      disable-legacy-endpoints = "true"
    }
    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }
  }

  networking_mode       = "VPC_NATIVE"
  datapath_provider     = "ADVANCED_DATAPATH"
  enable_shielded_nodes = true
  enable_legacy_abac    = false

  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = true
    master_ipv4_cidr_block  = var.master_ipv4_cidr_block
    master_global_access_config {
      enabled = true
    }
  }

  master_authorized_networks_config {
    gcp_public_cidrs_access_enabled      = false
    private_endpoint_enforcement_enabled = true
    dynamic "cidr_blocks" {
      for_each = var.control_plane_authorized_cidrs
      content {
        display_name = cidr_blocks.key
        cidr_block   = cidr_blocks.value
      }
    }
  }

  master_auth {
    client_certificate_config {
      issue_client_certificate = false
    }
  }

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  release_channel {
    channel = "REGULAR"
  }

  # Two 24-hour windows each week satisfy GKE's 48 hours / 32 days rule.
  maintenance_policy {
    recurring_window {
      start_time = "2026-01-03T00:00:00Z"
      end_time   = "2026-01-04T00:00:00Z"
      recurrence = "FREQ=WEEKLY;BYDAY=SA,SU"
    }
  }

  addons_config {
    http_load_balancing { disabled = false }
    horizontal_pod_autoscaling { disabled = false }
    gce_persistent_disk_csi_driver_config { enabled = true }
  }

  logging_config {
    enable_components = ["SYSTEM_COMPONENTS", "WORKLOADS", "APISERVER", "SCHEDULER", "CONTROLLER_MANAGER"]
  }
  monitoring_config {
    enable_components = ["SYSTEM_COMPONENTS"]
    managed_prometheus { enabled = true }
  }

  security_posture_config {
    mode               = "BASIC"
    vulnerability_mode = "VULNERABILITY_BASIC"
  }

  resource_labels = {
    environment = var.environment
    managed-by  = "opentofu"
  }

  lifecycle {
    precondition {
      condition     = length(local.zones) == 3
      error_message = "This production standard requires three available zones in the selected region."
    }
    precondition {
      condition     = endswith(data.google_compute_subnetwork.existing.network, "/networks/${local.network_name}")
      error_message = "The subnet must belong to the environment VPC."
    }
    precondition {
      condition     = alltrue([for name in ["pods", "services"] : contains([for range in data.google_compute_subnetwork.existing.secondary_ip_range : range.range_name], name)])
      error_message = "The existing subnet must have secondary ranges named pods and services."
    }
    precondition {
      condition     = data.google_compute_subnetwork.existing.private_ip_google_access
      error_message = "The network team must enable Private Google Access on the subnet for private nodes."
    }
  }

  depends_on = [google_project_iam_member.nodes]
}

resource "google_container_node_pool" "this" {
  for_each           = var.node_pools
  project            = var.project_id
  name               = each.key
  location           = var.region
  cluster            = google_container_cluster.this.name
  node_locations     = local.zones
  initial_node_count = each.value.min_nodes_per_zone
  max_pods_per_node  = 64

  autoscaling {
    min_node_count  = each.value.min_nodes_per_zone
    max_node_count  = each.value.max_nodes_per_zone
    location_policy = "BALANCED"
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  upgrade_settings {
    max_surge       = 1
    max_unavailable = 0
  }

  node_config {
    machine_type    = each.value.machine_type
    disk_size_gb    = each.value.disk_size_gb
    disk_type       = "pd-balanced"
    image_type      = "COS_CONTAINERD"
    service_account = google_service_account.nodes.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]
    spot            = false
    preemptible     = false
    labels          = merge(each.value.labels, { environment = var.environment })
    metadata = {
      disable-legacy-endpoints = "true"
    }
    workload_metadata_config {
      mode = "GKE_METADATA"
    }
    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }
  }
}

resource "google_service_account" "workload" {
  for_each     = var.workload_identities
  project      = var.project_id
  account_id   = "gke-w-${substr(sha256("${var.region}/${var.cluster_name}/${each.key}"), 0, 24)}"
  display_name = "GKE workload ${substr(each.key, 0, 70)}"
  depends_on   = [google_project_service.required]
}

resource "google_service_account_iam_member" "workload_identity" {
  for_each           = var.workload_identities
  service_account_id = google_service_account.workload[each.key].name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[${each.value.namespace}/${each.value.kubernetes_service_account}]"
  depends_on         = [google_container_cluster.this]
}

resource "google_project_iam_member" "workload" {
  for_each = local.workload_roles
  project  = var.project_id
  role     = each.value.role
  member   = "serviceAccount:${google_service_account.workload[each.value.key].email}"
}
