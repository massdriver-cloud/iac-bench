locals {
  cluster_labels = merge(var.labels, {
    environment = var.environment
    managed-by  = "opentofu"
  })
}

resource "google_container_cluster" "this" {
  name     = var.name
  project  = var.project_id
  location = var.region

  deletion_protection = var.deletion_protection

  network    = data.google_compute_network.apps.self_link
  subnetwork = data.google_compute_subnetwork.gke.self_link

  # Node pools are separate resources (node_pools.tf). The default pool is
  # removed so that every node runs with the hardened configuration.
  remove_default_node_pool = true
  initial_node_count       = 1

  release_channel {
    channel = var.release_channel
  }

  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = var.enable_private_endpoint
    master_ipv4_cidr_block  = var.control_plane_cidr
  }

  # This block is always present. Without it, GKE leaves the public endpoint
  # open to 0.0.0.0/0. With an empty list, public access is closed.
  master_authorized_networks_config {
    dynamic "cidr_blocks" {
      for_each = var.master_authorized_networks
      content {
        cidr_block   = cidr_blocks.value.cidr_block
        display_name = cidr_blocks.value.display_name
      }
    }
  }

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  # Dataplane V2 (eBPF). Enforces NetworkPolicy natively and provides flow
  # visibility without a separate network policy addon.
  datapath_provider     = "ADVANCED_DATAPATH"
  enable_shielded_nodes = true

  # Disables the externalIPs field on Services, which closes a known path for
  # traffic interception inside the cluster.
  service_external_ips_config {
    enabled = false
  }

  gateway_api_config {
    channel = "CHANNEL_STANDARD"
  }

  vertical_pod_autoscaling {
    enabled = true
  }

  addons_config {
    horizontal_pod_autoscaling {
      disabled = false
    }
    http_load_balancing {
      disabled = false
    }
    gce_persistent_disk_csi_driver_config {
      enabled = true
    }
    # Lets workloads mount Cloud Storage buckets as volumes through Workload Identity.
    gcs_fuse_csi_driver_config {
      enabled = true
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

  security_posture_config {
    mode               = "BASIC"
    vulnerability_mode = "VULNERABILITY_BASIC"
  }

  dynamic "database_encryption" {
    for_each = var.secrets_encryption_key == null ? [] : [var.secrets_encryption_key]
    content {
      state    = "ENCRYPTED"
      key_name = database_encryption.value
    }
  }

  dynamic "notification_config" {
    for_each = var.upgrade_notification_topic == null ? [] : [var.upgrade_notification_topic]
    content {
      pubsub {
        enabled = true
        topic   = notification_config.value
      }
    }
  }

  maintenance_policy {
    recurring_window {
      start_time = var.maintenance_window.start_time
      end_time   = var.maintenance_window.end_time
      recurrence = var.maintenance_window.recurrence
    }
  }

  resource_labels = local.cluster_labels

  depends_on = [
    google_kms_crypto_key_iam_member.gke_secrets,
  ]
}
