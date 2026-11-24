resource "google_container_cluster" "this" {
  name     = var.cluster_name
  project  = var.project_id
  location = var.region

  node_locations = length(var.node_locations) > 0 ? var.node_locations : null

  # Standard GKE best practice: remove the default pool and manage all node pools explicitly.
  remove_default_node_pool = true
  initial_node_count       = 1

  deletion_protection = var.deletion_protection
  resource_labels     = local.common_labels

  # VPC-native networking using the network team's pre-provisioned subnet and secondary ranges.
  networking_mode = "VPC_NATIVE"
  network         = local.network_id
  subnetwork      = local.subnet_id

  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  # Dataplane V2 (eBPF) includes built-in Kubernetes NetworkPolicy enforcement and observability.
  datapath_provider           = "ADVANCED_DATAPATH"
  enable_intranode_visibility = true
  enable_l4_ilb_subsetting    = true

  # Security hardening: private nodes, shielded nodes, no legacy ABAC, no client certs.
  enable_shielded_nodes = true
  enable_legacy_abac    = false

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = var.enable_private_endpoint
    master_ipv4_cidr_block  = var.master_ipv4_cidr_block

    master_global_access_config {
      enabled = var.enable_private_endpoint
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

  master_auth {
    client_certificate_config {
      issue_client_certificate = false
    }
  }

  # Workload Identity lets product-team pods authenticate to Pub/Sub, Cloud Storage, Cloud SQL, etc. without keys.
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  security_posture_config {
    mode               = "BASIC"
    vulnerability_mode = "VULNERABILITY_BASIC"
  }

  binary_authorization {
    evaluation_mode = var.enable_binary_authorization ? "PROJECT_SINGLETON_POLICY_ENFORCE" : "DISABLED"
  }

  database_encryption {
    state    = var.etcd_kms_key_id != null ? "ENCRYPTED" : "DECRYPTED"
    key_name = var.etcd_kms_key_id
  }

  dynamic "authenticator_groups_config" {
    for_each = var.security_group != null ? [var.security_group] : []
    content {
      security_group = authenticator_groups_config.value
    }
  }

  # Lifecycle & upgrade resilience.
  release_channel {
    channel = var.release_channel
  }

  maintenance_policy {
    recurring_window {
      start_time = var.maintenance_window_start_time
      end_time   = var.maintenance_window_end_time
      recurrence = var.maintenance_window_recurrence
    }
  }

  cluster_autoscaling {
    autoscaling_profile = var.autoscaling_profile
  }

  # Cluster add-ons and multi-team operational features.
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

    dns_cache_config {
      enabled = true
    }
  }

  gateway_api_config {
    channel = "CHANNEL_STANDARD"
  }

  vertical_pod_autoscaling {
    enabled = var.enable_vertical_pod_autoscaling
  }

  cost_management_config {
    enabled = true
  }

  logging_config {
    enable_components = ["SYSTEM_COMPONENTS", "WORKLOADS"]
  }

  monitoring_config {
    enable_components = ["SYSTEM_COMPONENTS", "APISERVER", "SCHEDULER", "CONTROLLER_MANAGER"]

    managed_prometheus {
      enabled = true
    }

    advanced_datapath_observability_config {
      enable_metrics = true
      enable_relay   = true
    }
  }

  dynamic "notification_config" {
    for_each = var.notification_pubsub_topic != null ? [var.notification_pubsub_topic] : []
    content {
      pubsub {
        enabled = true
        topic   = notification_config.value
      }
    }
  }

  depends_on = [google_project_iam_member.nodes]
}

resource "google_container_node_pool" "pools" {
  for_each = var.node_pools

  name     = each.key
  project  = var.project_id
  location = var.region
  cluster  = google_container_cluster.this.name

  node_locations     = length(each.value.node_locations) > 0 ? each.value.node_locations : null
  initial_node_count = each.value.min_node_count

  autoscaling {
    min_node_count  = each.value.min_node_count
    max_node_count  = each.value.max_node_count
    location_policy = each.value.location_policy
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
    image_type   = each.value.image_type
    disk_type    = each.value.disk_type
    disk_size_gb = each.value.disk_size_gb
    spot         = each.value.spot

    service_account = google_service_account.nodes.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]

    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    gcfs_config {
      enabled = each.value.enable_image_streaming
    }

    metadata = {
      disable-legacy-endpoints = "true"
    }

    labels = merge(
      {
        "cluster"     = var.cluster_name
        "environment" = var.environment
        "node-pool"   = each.key
      },
      each.value.labels
    )

    resource_labels = merge(
      local.common_labels,
      {
        "node_pool" = each.key
      }
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

  lifecycle {
    ignore_changes = [initial_node_count]
  }
}
