locals {
  # Resolve VPC network name from environment or direct override
  vpc_name = var.vpc_name != null ? var.vpc_name : (
    startswith(var.environment, "apps-") ? var.environment : "apps-${var.environment}"
  )

  # Subnet naming follows network team convention: <vpc>-gke-<region>
  subnetwork = var.subnetwork != null ? var.subnetwork : "${local.vpc_name}-gke-${var.region}"

  # Node service account account_id: alphanumeric with dashes, max 30 chars
  node_sa_account_id = var.service_account_id != null ? var.service_account_id : trimsuffix(substr(lower("${var.cluster_name}-node-sa"), 0, 30), "-")

  node_service_account_email = var.create_service_account ? (
    length(google_service_account.node_sa) > 0 ? google_service_account.node_sa[0].email : null
  ) : var.service_account_email

  # Least-privilege IAM roles for GKE worker nodes
  default_node_sa_roles = [
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/monitoring.viewer",
    "roles/stackdriver.resourceMetadata.writer",
    "roles/artifactregistry.reader"
  ]

  node_sa_roles = var.create_service_account ? concat(local.default_node_sa_roles, var.additional_node_sa_roles) : []
}

# Dedicated least-privileged IAM service account for the cluster's worker nodes
resource "google_service_account" "node_sa" {
  count        = var.create_service_account ? 1 : 0
  account_id   = local.node_sa_account_id
  display_name = "GKE Node Service Account for ${var.cluster_name}"
  project      = var.project_id
  description  = "Dedicated least-privilege service account for GKE worker nodes in cluster ${var.cluster_name}"
}

# Assign required node roles to the dedicated service account
resource "google_project_iam_member" "node_sa_roles" {
  for_each = toset(local.node_sa_roles)

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.node_sa[0].email}"
}

# GKE Standard production cluster
resource "google_container_cluster" "primary" {
  name     = var.cluster_name
  location = var.region
  project  = var.project_id

  # GKE Standard best practice: remove the default node pool to manage node pools independently
  remove_default_node_pool = true
  initial_node_count       = 1

  # Network and subnetwork configured by the network team
  network    = local.vpc_name
  subnetwork = local.subnetwork

  # VPC-native routing with secondary IP ranges for pods and services
  ip_allocation_policy {
    cluster_secondary_range_name  = var.cluster_secondary_range_name
    services_secondary_range_name = var.services_secondary_range_name
  }

  # Production private cluster configuration: nodes have no public IP addresses
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = var.enable_private_endpoint
    master_ipv4_cidr_block  = var.master_ipv4_cidr_block

    master_global_access_config {
      enabled = true
    }
  }

  # Workload Identity: secure IAM access for pods to GCP services (Pub/Sub, Storage, Cloud SQL)
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  # Datapath v2 (eBPF / Cilium): high performance, built-in NetworkPolicy enforcement, flow logs
  datapath_provider = "ADVANCED_DATAPATH"

  # Hardware-level security: cryptographic integrity monitoring and secure boot
  enable_shielded_nodes = true

  # Intranode visibility: ensures intra-node pod traffic is subject to VPC firewall rules and logging
  enable_intranode_visibility = true

  # Release channel for managed, automated GKE upgrades
  release_channel {
    channel = var.release_channel
  }

  # Predictable maintenance window for non-disruptive upgrades
  maintenance_policy {
    recurring_window {
      start_time = var.maintenance_start_time
      end_time   = var.maintenance_end_time
      recurrence = var.maintenance_recurrence
    }
  }

  # Production cluster addons
  addons_config {
    http_load_balancing {
      disabled = false
    }

    horizontal_pod_autoscaling {
      disabled = false
    }

    # Enables pods to mount Google Cloud Storage buckets natively as volumes
    gcs_fuse_csi_driver_config {
      enabled = var.enable_gcs_fuse_csi_driver
    }

    # In-cluster DNS caching for low-latency, resilient DNS lookup
    dns_cache_config {
      enabled = var.enable_dns_cache
    }
  }

  # Security posture and vulnerability detection
  security_posture_config {
    mode               = "BASIC"
    vulnerability_mode = "VULNERABILITY_BASIC"
  }

  # Master authorized networks to restrict API server access
  dynamic "master_authorized_networks_config" {
    for_each = var.enable_master_authorized_networks || length(var.master_authorized_networks) > 0 ? [1] : []
    content {
      gcp_public_cidrs_access_enabled = var.master_authorized_networks_gcp_public_cidrs_access_enabled
      dynamic "cidr_blocks" {
        for_each = var.master_authorized_networks
        content {
          cidr_block   = cidr_blocks.value.cidr_block
          display_name = lookup(cidr_blocks.value, "display_name", null)
        }
      }
    }
  }

  # Optional Cloud KMS CMEK encryption for Kubernetes secrets in etcd
  dynamic "database_encryption" {
    for_each = var.database_encryption_key_name != null ? [1] : []
    content {
      state    = "ENCRYPTED"
      key_name = var.database_encryption_key_name
    }
  }

  # Comprehensive Cloud Logging and Monitoring
  logging_config {
    enable_components = var.logging_components
  }

  monitoring_config {
    enable_components = var.monitoring_components
    managed_prometheus {
      enabled = var.enable_managed_prometheus
    }
  }

  deletion_protection = var.deletion_protection

  resource_labels = merge(
    {
      "environment" = var.environment
      "managed-by"  = "opentofu"
    },
    var.cluster_labels
  )

  lifecycle {
    ignore_changes = [
      # Ignore changes to initial_node_count as the default pool is immediately removed
      initial_node_count,
    ]
  }
}

# Production GKE Standard Node Pools
resource "google_container_node_pool" "pools" {
  for_each = var.node_pools

  name           = each.key
  location       = var.region
  cluster        = google_container_cluster.primary.name
  project        = var.project_id
  node_locations = each.value.node_locations

  initial_node_count = each.value.initial_node_count

  autoscaling {
    min_node_count = each.value.min_node_count
    max_node_count = each.value.max_node_count
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  # Zero-downtime rolling upgrades
  upgrade_settings {
    max_surge       = 1
    max_unavailable = 0
  }

  node_config {
    machine_type = each.value.machine_type
    disk_size_gb = each.value.disk_size_gb
    disk_type    = each.value.disk_type
    image_type   = each.value.image_type
    spot         = each.value.spot

    service_account = local.node_service_account_email
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]

    # Enables Workload Identity on nodes; secures instance metadata
    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    labels = merge(
      {
        "environment" = var.environment
        "node-pool"   = each.key
      },
      each.value.labels
    )

    tags = concat(["gke-node", "${var.cluster_name}-node"], each.value.tags)

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
  }

  lifecycle {
    ignore_changes = [
      initial_node_count,
    ]
  }

  depends_on = [
    google_project_iam_member.node_sa_roles
  ]
}
