resource "google_container_cluster" "this" {
  name     = var.cluster_name
  location = var.region
  project  = var.project_id

  # Use dedicated, separately managed node pools instead of the default pool.
  remove_default_node_pool = true
  initial_node_count       = 1

  deletion_protection = var.deletion_protection
  min_master_version  = var.kubernetes_version

  release_channel {
    channel = var.release_channel
  }

  # Network team's pre-provisioned VPC and regional GKE subnet.
  network    = local.network_self_link
  subnetwork = local.subnetwork_self_link

  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  # Dataplane V2 (eBPF) provides built-in NetworkPolicy enforcement and load balancing.
  datapath_provider           = "ADVANCED_DATAPATH"
  enable_intranode_visibility = true
  enable_l4_ilb_subsetting    = true

  # Cloud DNS for GKE eliminates kube-dns scaling and conntrack bottlenecks.
  dns_config {
    cluster_dns       = "CLOUD_DNS"
    cluster_dns_scope = "CLUSTER_SCOPE"
  }

  # Private nodes with restricted API server access.
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = var.enable_private_endpoint
    master_ipv4_cidr_block  = var.master_ipv4_cidr_block

    master_global_access_config {
      enabled = var.enable_master_global_access
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

  # Disable legacy client certificate issuance.
  master_auth {
    client_certificate_config {
      issue_client_certificate = false
    }
  }

  # Workload Identity enables least-privilege IAM for pods calling Pub/Sub, GCS, Cloud SQL, etc.
  workload_identity_config {
    workload_pool = local.workload_identity_pool
  }

  # Shielded GKE Nodes protect against rootkits and boot-level tampering.
  enable_shielded_nodes = true

  # Security posture and basic vulnerability scanning.
  security_posture_config {
    mode               = "BASIC"
    vulnerability_mode = "VULNERABILITY_BASIC"
  }

  # Binary Authorization (optional enforcement).
  binary_authorization {
    evaluation_mode = var.enable_binary_authorization ? "PROJECT_SINGLETON_POLICY_ENFORCE" : "DISABLED"
  }

  # Customer-managed encryption key for Kubernetes Secrets in etcd (if supplied).
  database_encryption {
    state    = var.etcd_kms_key_name != null ? "ENCRYPTED" : "DECRYPTED"
    key_name = var.etcd_kms_key_name
  }

  # Optional Google Workspace Groups integration for Kubernetes RBAC.
  dynamic "authenticator_groups_config" {
    for_each = var.authenticator_security_group != null ? [var.authenticator_security_group] : []
    content {
      security_group = authenticator_groups_config.value
    }
  }

  # Multi-team cost visibility by namespace and label.
  cost_management_config {
    enabled = true
  }

  # Kubernetes Gateway API and Vertical Pod Autoscaling.
  gateway_api_config {
    channel = "CHANNEL_STANDARD"
  }

  vertical_pod_autoscaling {
    enabled = true
  }

  # Cluster autoscaling profile tuned for production headroom.
  cluster_autoscaling {
    autoscaling_profile = "BALANCED"
  }

  # Add-ons: Ingress, HPA, PD CSI, GCS FUSE CSI, Filestore CSI, Backup for GKE.
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
      enabled = var.enable_gcs_fuse_csi_driver
    }

    gcp_filestore_csi_driver_config {
      enabled = var.enable_filestore_csi_driver
    }

    gke_backup_agent_config {
      enabled = var.enable_gke_backup_agent
    }
  }

  secret_manager_config {
    enabled = var.enable_secret_manager_addon
  }

  # Observability: System + Workload logging, control plane & K8s metrics, Dataplane V2 metrics, Managed Prometheus.
  logging_config {
    enable_components = ["SYSTEM_COMPONENTS", "WORKLOADS"]
  }

  monitoring_config {
    enable_components = [
      "SYSTEM_COMPONENTS",
      "APISERVER",
      "SCHEDULER",
      "CONTROLLER_MANAGER",
      "STORAGE",
      "POD",
      "DEPLOYMENT",
      "STATEFULSET",
      "DAEMONSET",
      "HPA",
    ]

    managed_prometheus {
      enabled = var.enable_managed_prometheus
    }

    advanced_datapath_observability_config {
      enable_metrics = true
      enable_relay   = false
    }
  }

  # Predictable off-peak maintenance window with optional exclusion windows.
  maintenance_policy {
    recurring_window {
      start_time = var.maintenance_window.start_time
      end_time   = var.maintenance_window.end_time
      recurrence = var.maintenance_window.recurrence
    }

    dynamic "maintenance_exclusion" {
      for_each = var.maintenance_exclusions
      content {
        exclusion_name = maintenance_exclusion.value.name
        start_time     = maintenance_exclusion.value.start_time
        end_time       = maintenance_exclusion.value.end_time
        exclusion_options {
          scope = maintenance_exclusion.value.scope
        }
      }
    }
  }

  resource_labels = local.common_labels

  lifecycle {
    ignore_changes = [
      initial_node_count,
    ]
  }
}

resource "google_container_node_pool" "pools" {
  for_each = var.node_pools

  name           = each.key
  cluster        = google_container_cluster.this.id
  location       = var.region
  project        = var.project_id
  node_locations = length(each.value.node_locations) > 0 ? each.value.node_locations : null

  initial_node_count = each.value.min_nodes_per_zone

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
    strategy        = "SURGE"
    max_surge       = each.value.max_surge
    max_unavailable = each.value.max_unavailable
  }

  node_config {
    machine_type = each.value.machine_type
    disk_size_gb = each.value.disk_size_gb
    disk_type    = each.value.disk_type
    image_type   = "COS_CONTAINERD"
    spot         = each.value.spot

    service_account = google_service_account.gke_nodes.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]

    gvnic {
      enabled = true
    }

    # Force pods to use Workload Identity instead of the node's metadata identity.
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
      {
        "environment" = var.environment
        "node-pool"   = each.key
      },
      each.value.labels
    )

    resource_labels = local.common_labels

    tags = [
      "gke-node",
      local.vpc_name,
      local.cluster_node_tag,
    ]

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

# Allow the private control plane to reach Kubernetes admission/conversion webhooks on cluster nodes.
resource "google_compute_firewall" "master_webhooks" {
  count = var.create_master_webhook_firewall_rule && length(var.master_webhook_ports) > 0 ? 1 : 0

  name        = "gke-${var.cluster_name}-master-webhooks"
  description = "Allow GKE control plane for ${var.cluster_name} to reach admission webhooks on nodes."
  project     = var.project_id
  network     = local.network_self_link
  direction   = "INGRESS"

  source_ranges = [var.master_ipv4_cidr_block]
  target_tags   = [local.cluster_node_tag]

  allow {
    protocol = "tcp"
    ports    = var.master_webhook_ports
  }
}
