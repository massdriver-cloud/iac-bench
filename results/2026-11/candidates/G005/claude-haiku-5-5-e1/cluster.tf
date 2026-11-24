locals {
  is_prod = var.environment == "prod"

  common_labels = merge(var.labels, {
    environment = var.environment
    managed-by  = "opentofu"
  })
}

resource "google_container_cluster" "this" {
  name     = var.cluster_name
  project  = var.project_id
  location = var.region

  deletion_protection = var.deletion_protection

  # Regional control plane; nodes come from google_container_node_pool.
  # The default pool is removed so every pool is managed by this module.
  remove_default_node_pool = true
  initial_node_count       = 1

  resource_labels = local.common_labels

  # VPC-native cluster on the network team's shared subnet.
  network    = data.google_compute_network.vpc.self_link
  subnetwork = data.google_compute_subnetwork.gke.self_link

  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
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

  # Dataplane V2 (eBPF) enforces Kubernetes NetworkPolicy natively,
  # so no separate network policy add-on is configured.
  datapath_provider           = "ADVANCED_DATAPATH"
  enable_intranode_visibility = true
  enable_l4_ilb_subsetting    = true

  # Block Services that set externalIPs, a common path to traffic hijacking.
  service_external_ips_config {
    enabled = false
  }

  gateway_api_config {
    channel = "CHANNEL_STANDARD"
  }

  # Pods authenticate as Google service accounts via Workload Identity.
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  enable_shielded_nodes = true

  binary_authorization {
    evaluation_mode = "PROJECT_SINGLETON_POLICY_ENFORCE"
  }

  # Application-layer encryption of Secrets in etcd. Uses Google-managed keys unless a KMS key is supplied.
  database_encryption {
    state    = var.database_encryption_key == null ? "DECRYPTED" : "ENCRYPTED"
    key_name = var.database_encryption_key
  }

  security_posture_config {
    mode               = "BASIC"
    vulnerability_mode = "VULNERABILITY_BASIC"
  }

  logging_config {
    enable_components = ["SYSTEM_COMPONENTS", "WORKLOADS"]
  }

  monitoring_config {
    enable_components = [
      "SYSTEM_COMPONENTS",
      "POD",
      "DEPLOYMENT",
      "STATEFULSET",
      "DAEMONSET",
      "HPA",
      "STORAGE",
      "CADVISOR",
      "KUBELET",
    ]

    managed_prometheus {
      enabled = true
    }
  }

  addons_config {
    http_load_balancing {
      disabled = false
    }

    horizontal_pod_autoscaling {
      disabled = false
    }

    # Lets workloads mount Cloud Storage buckets and Persistent Disks as volumes.
    gce_persistent_disk_csi_driver_config {
      enabled = true
    }

    gcs_fuse_csi_driver_config {
      enabled = true
    }

    gcp_filestore_csi_driver_config {
      enabled = false
    }
  }

  vertical_pod_autoscaling {
    enabled = true
  }

  lifecycle {
    precondition {
      condition     = !local.is_prod || var.release_channel != "RAPID"
      error_message = "Production clusters must not use the RAPID release channel."
    }

    precondition {
      condition     = !local.is_prod || var.deletion_protection
      error_message = "Production clusters must keep deletion_protection enabled."
    }

    precondition {
      condition     = !local.is_prod || alltrue([for k, p in var.node_pools : !p.spot])
      error_message = "Spot node pools are not allowed in production clusters."
    }

    precondition {
      condition     = data.google_compute_subnetwork.gke.private_ip_google_access
      error_message = "Subnet ${local.subnet_name} must have Private Google Access enabled so private nodes can reach Pub/Sub, Cloud Storage, and other Google APIs."
    }

    precondition {
      condition     = contains([for r in data.google_compute_subnetwork.gke.secondary_ip_range : r.range_name], "pods") && contains([for r in data.google_compute_subnetwork.gke.secondary_ip_range : r.range_name], "services")
      error_message = "Subnet ${local.subnet_name} must define secondary ranges named \"pods\" and \"services\"."
    }
  }
}
