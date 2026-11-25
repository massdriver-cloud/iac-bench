locals {
  vpc_name               = "apps-${var.environment}"
  subnet_name            = "${local.vpc_name}-gke-${var.region}"
  network_self_link      = "projects/${var.project_id}/global/networks/${local.vpc_name}"
  subnetwork_self_link   = "projects/${var.project_id}/regions/${var.region}/subnetworks/${local.subnet_name}"
  pods_range_name        = "pods"
  services_range_name    = "services"
  workload_identity_pool = "${var.project_id}.svc.id.goog"

  common_labels = merge(
    {
      environment = var.environment
      cluster     = var.cluster_name
      managed_by  = "opentofu"
    },
    var.labels
  )

  node_service_account_roles = toset([
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/monitoring.viewer",
    "roles/stackdriver.resourceMetadata.writer",
    "roles/artifactregistry.reader",
  ])
}

# Dedicated least-privilege IAM Service Account for GKE nodes
resource "google_service_account" "cluster_nodes" {
  project      = var.project_id
  account_id   = substr("${var.cluster_name}-nodes", 0, 28)
  display_name = "GKE Node Service Account for ${var.cluster_name}"
  description  = "Dedicated least-privilege node service account for GKE cluster ${var.cluster_name}"
}

resource "google_project_iam_member" "cluster_nodes" {
  for_each = local.node_service_account_roles

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.cluster_nodes.email}"
}

# Regional GKE Standard Cluster
resource "google_container_cluster" "primary" {
  project  = var.project_id
  name     = var.cluster_name
  location = var.region

  # GKE Standard best practice: remove default node pool and manage dedicated node pools
  remove_default_node_pool = true
  initial_node_count       = 1

  deletion_protection = var.deletion_protection
  resource_labels     = local.common_labels

  # Networking configuration adhering to network team's VPC & subnet conventions
  network         = local.network_self_link
  subnetwork      = local.subnetwork_self_link
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
    for_each = length(var.master_authorized_networks) > 0 ? [1] : []
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

  # Dataplane V2 (Cilium/eBPF) provides built-in Kubernetes NetworkPolicy enforcement & observability
  datapath_provider = "ADVANCED_DATAPATH"

  # Workload Identity for keyless pod authentication to Pub/Sub, Cloud Storage, Cloud SQL, etc.
  workload_identity_config {
    workload_pool = local.workload_identity_pool
  }

  # Shielded GKE Nodes for verifiable node integrity
  enable_shielded_nodes = true

  # Automated release channel upgrades
  release_channel {
    channel = var.release_channel
  }

  # Maintenance window: weekends 04:00 - 08:00 UTC to minimize impact on business hours
  maintenance_policy {
    recurring_window {
      start_time = "2024-01-06T04:00:00Z"
      end_time   = "2024-01-06T08:00:00Z"
      recurrence = "FREQ=WEEKLY;BYDAY=SA,SU"
    }
  }

  # Core production addons
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

  # Observability: Cloud Logging and Cloud Monitoring with Managed Prometheus
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
      "STORAGE",
      "HPA",
      "POD",
      "DAEMONSET",
      "DEPLOYMENT",
      "STATEFULSET",
    ]

    managed_prometheus {
      enabled = true
    }
  }

  # Multi-tenant cost allocation tracking per namespace/label
  cost_management_config {
    enabled = true
  }

  # Security Posture Management
  security_posture_config {
    mode               = "BASIC"
    vulnerability_mode = "VULNERABILITY_BASIC"
  }

  # Binary Authorization capability
  binary_authorization {
    evaluation_mode = "PROJECT_SINGLETON_POLICY_ENFORCE"
  }

  # Optional KMS encryption for etcd secrets
  dynamic "database_encryption" {
    for_each = var.kms_key_self_link != null ? [1] : []
    content {
      state    = "ENCRYPTED"
      key_name = var.kms_key_self_link
    }
  }

  # Optional Pub/Sub cluster notifications
  dynamic "notification_config" {
    for_each = var.notification_pubsub_topic != null ? [1] : []
    content {
      pubsub {
        enabled = true
        topic   = var.notification_pubsub_topic
      }
    }
  }

  # Vertical Pod Autoscaling support
  vertical_pod_autoscaling {
    enabled = true
  }
}

# Managed Regional Node Pools
resource "google_container_node_pool" "pools" {
  for_each = var.node_pools

  project  = var.project_id
  name     = each.key
  location = var.region
  cluster  = google_container_cluster.primary.name

  node_locations = each.value.node_locations

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

    # Route pod metadata requests to the GKE metadata server (required for Workload Identity)
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

    resource_labels = merge(
      local.common_labels,
      {
        node_pool = each.key
      },
      each.value.labels
    )

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
}
