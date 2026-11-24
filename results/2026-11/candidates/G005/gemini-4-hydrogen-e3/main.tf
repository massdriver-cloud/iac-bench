resource "google_container_cluster" "this" {
  project  = var.project_id
  name     = var.cluster_name
  location = var.region

  node_locations = length(var.node_locations) > 0 ? var.node_locations : null

  # GKE Standard: remove the default pool on creation and manage pools explicitly below.
  remove_default_node_pool = true
  initial_node_count       = 1

  deletion_protection = var.deletion_protection
  resource_labels     = local.cluster_labels

  # VPC-native networking using the network team's pre-provisioned VPC, subnet, and secondary ranges.
  network         = local.network_self_link
  subnetwork      = local.subnetwork_self_link
  networking_mode = "VPC_NATIVE"

  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  default_max_pods_per_node = var.default_max_pods_per_node

  # Dataplane V2 (eBPF/Cilium) provides native NetworkPolicy enforcement and observability for multi-team isolation.
  datapath_provider           = "ADVANCED_DATAPATH"
  enable_intranode_visibility = true
  enable_l4_ilb_subsetting    = true
  enable_shielded_nodes       = true
  enable_legacy_abac          = false

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = var.enable_private_endpoint
    master_ipv4_cidr_block  = var.master_ipv4_cidr_block

    master_global_access_config {
      enabled = true
    }
  }

  master_authorized_networks_config {
    gcp_public_cidrs_access_enabled = var.gcp_public_cidrs_access_enabled

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

  # Workload Identity Federation allows pods to impersonate least-privilege GSAs for Pub/Sub, GCS, and Cloud SQL.
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  # Cloud DNS removes kube-dns scaling bottlenecks in multi-tenant clusters.
  dns_config {
    cluster_dns       = "CLOUD_DNS"
    cluster_dns_scope = "CLUSTER_SCOPE"
  }

  gateway_api_config {
    channel = "CHANNEL_STANDARD"
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

  cluster_autoscaling {
    autoscaling_profile = var.autoscaling_profile
  }

  vertical_pod_autoscaling {
    enabled = true
  }

  cost_management_config {
    enabled = true
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

    gke_backup_agent_config {
      enabled = var.enable_backup_agent
    }

    # NodeLocal DNSCache is incompatible with Cloud DNS for GKE.
    dns_cache_config {
      enabled = false
    }
  }

  secret_manager_config {
    enabled = var.enable_secret_manager_addon
  }

  logging_config {
    enable_components = var.logging_components
  }

  monitoring_config {
    enable_components = var.monitoring_components

    managed_prometheus {
      enabled = var.enable_managed_prometheus
    }
  }

  security_posture_config {
    mode               = "BASIC"
    vulnerability_mode = "VULNERABILITY_BASIC"
  }

  binary_authorization {
    evaluation_mode = var.binary_authorization_mode
  }

  dynamic "database_encryption" {
    for_each = var.database_encryption_key_id != null ? [var.database_encryption_key_id] : []
    content {
      state    = "ENCRYPTED"
      key_name = database_encryption.value
    }
  }

  dynamic "authenticator_groups_config" {
    for_each = var.gke_security_group != null ? [var.gke_security_group] : []
    content {
      security_group = authenticator_groups_config.value
    }
  }

  dynamic "notification_config" {
    for_each = var.notification_topic_id != null ? [var.notification_topic_id] : []
    content {
      pubsub {
        enabled = true
        topic   = notification_config.value
      }
    }
  }

  lifecycle {
    ignore_changes = [initial_node_count]
  }
}

resource "google_container_node_pool" "pools" {
  for_each = var.node_pools

  project  = var.project_id
  name     = each.key
  location = var.region
  cluster  = google_container_cluster.this.name

  node_locations     = each.value.node_locations
  initial_node_count = each.value.initial_node_count
  max_pods_per_node  = each.value.max_pods_per_node

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

  network_config {
    enable_private_nodes = true
  }

  node_config {
    machine_type    = each.value.machine_type
    disk_size_gb    = each.value.disk_size_gb
    disk_type       = each.value.disk_type
    image_type      = each.value.image_type
    spot            = each.value.spot
    service_account = google_service_account.nodes.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]

    labels = merge(
      {
        environment = var.environment
        node-pool   = each.key
      },
      each.value.labels,
    )

    tags = concat(["gke-node", "${var.cluster_name}-node"], each.value.tags)

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

    gcfs_config {
      enabled = each.value.enable_image_streaming
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
    ignore_changes = [initial_node_count]
  }

  depends_on = [google_project_iam_member.nodes]
}
