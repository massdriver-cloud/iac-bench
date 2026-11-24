locals {
  network    = "apps-${var.environment}"
  subnetwork = "${local.network}-gke-${var.region}"

  labels = merge(
    {
      environment = var.environment
      managed-by  = "opentofu"
    },
    var.labels,
  )

  # Flatten workload SA -> project role pairs for IAM bindings.
  workload_sa_roles = {
    for pair in flatten([
      for id, sa in var.workload_service_accounts : [
        for role in sa.project_roles : {
          key  = "${id}:${role}"
          id   = id
          role = role
        }
      ]
    ]) : pair.key => pair
  }
}

############################################
# Node service account (least privilege)
############################################

resource "google_service_account" "nodes" {
  account_id   = "${var.name}-nodes"
  display_name = "GKE node service account for cluster ${var.name}"
  description  = "Used by GKE nodes of ${var.name}; workloads use Workload Identity instead."
}

# Only what nodes need: ship logs/metrics and pull images.
resource "google_project_iam_member" "nodes" {
  for_each = toset([
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/monitoring.viewer",
    "roles/stackdriver.resourceMetadata.writer",
    "roles/artifactregistry.reader",
  ])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.nodes.email}"
}

############################################
# Cluster
############################################

resource "google_container_cluster" "this" {
  name        = var.name
  location    = var.region # regional: HA control plane, nodes across all zones
  description = "GKE Standard cluster for ${var.environment} workloads (platform-managed)."

  network    = local.network
  subnetwork = local.subnetwork

  deletion_protection = var.deletion_protection
  resource_labels     = local.labels

  # Node pools are managed as separate resources so they can be changed without recreating the cluster.
  remove_default_node_pool = true
  initial_node_count       = 1

  release_channel {
    channel = var.release_channel
  }

  # VPC-native using the network team's secondary ranges.
  networking_mode = "VPC_NATIVE"
  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  # Dataplane V2: eBPF networking with built-in NetworkPolicy enforcement and flow logs.
  datapath_provider = "ADVANCED_DATAPATH"

  # Nodes have no public IPs; API endpoint restricted to authorized networks.
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

  # Workload Identity: pods authenticate to Google APIs as Google service accounts, no exported keys.
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  # No legacy auth paths.
  master_auth {
    client_certificate_config {
      issue_client_certificate = false
    }
  }

  enable_shielded_nodes       = true
  enable_intranode_visibility = true

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

  security_posture_config {
    mode               = "BASIC"
    vulnerability_mode = "VULNERABILITY_BASIC"
  }

  maintenance_policy {
    recurring_window {
      start_time = var.maintenance_window.start_time
      end_time   = var.maintenance_window.end_time
      recurrence = var.maintenance_window.recurrence
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

  # Per-namespace cost breakdown in billing export; clusters are shared by several teams.
  cost_management_config {
    enabled = true
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

  lifecycle {
    ignore_changes = [
      # The default pool is deleted right after creation; its spec is irrelevant afterwards.
      initial_node_count,
    ]
  }

  depends_on = [google_project_iam_member.nodes]
}

############################################
# Node pools
############################################

resource "google_container_node_pool" "this" {
  for_each = var.node_pools

  name     = each.key
  cluster  = google_container_cluster.this.id
  location = var.region

  # Per-zone count; the pool spans every zone of the region.
  initial_node_count = each.value.min_nodes_per_zone

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

    labels = merge(
      { environment = var.environment, pool = each.key },
      each.value.labels,
    )
    resource_labels = local.labels

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

    metadata = {
      disable-legacy-endpoints = "true"
    }

    tags = ["gke-${var.name}", "gke-${var.name}-${each.key}"]
  }

  lifecycle {
    ignore_changes = [
      # Autoscaler owns the actual node count.
      initial_node_count,
    ]
  }
}

############################################
# Workload Identity service accounts for product teams
############################################

resource "google_service_account" "workload" {
  for_each = var.workload_service_accounts

  account_id   = each.key
  display_name = "Workload ${each.key} on ${var.name} (${each.value.namespace}/${each.value.kubernetes_service_account})"
}

resource "google_service_account_iam_member" "workload_identity" {
  for_each = var.workload_service_accounts

  service_account_id = google_service_account.workload[each.key].name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[${each.value.namespace}/${each.value.kubernetes_service_account}]"
}

resource "google_project_iam_member" "workload" {
  for_each = local.workload_sa_roles

  project = var.project_id
  role    = each.value.role
  member  = "serviceAccount:${google_service_account.workload[each.value.id].email}"
}
