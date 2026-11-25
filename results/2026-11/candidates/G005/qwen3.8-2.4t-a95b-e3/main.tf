# A regional GKE Standard cluster: the control plane is replicated across all
# zones of the region and nodes are distributed automatically, which is the
# resilience baseline for shared production clusters.
resource "google_container_cluster" "this" {
  provider = google

  project     = local.project_id
  name        = var.cluster_name
  location    = var.region
  description = "GKE Standard production cluster \"${var.cluster_name}\", managed by the platform team's OpenTofu module."

  # --- Control plane ---------------------------------------------------------

  release_channel {
    channel = var.release_channel
  }

  min_master_version = var.kubernetes_version

  maintenance_policy {
    recurring_window {
      start_time = var.maintenance_start_time_utc
      end_time   = var.maintenance_end_time_utc
      recurrence = var.maintenance_recurrence
    }
  }

  dynamic "database_encryption" {
    for_each = var.database_encryption_kms_key == null ? [] : [var.database_encryption_kms_key]
    content {
      state    = "ENCRYPTED"
      key_name = database_encryption.value
    }
  }

  # --- Networking ------------------------------------------------------------
  # VPC-native (alias IP) cluster on the environment VPC. Subnet and secondary
  # range names follow the network team's conventions; node and service CIDRs
  # are therefore owned by the network team, not by this module.

  network         = local.network_name
  subnetwork      = local.subnetwork_name
  networking_mode = "VPC_NATIVE"

  ip_allocation_policy {
    cluster_secondary_range_name  = local.pods_range
    services_secondary_range_name = local.services_range
  }

  # Dataplane V2: eBPF-based networking with built-in network policy
  # enforcement and observability.
  datapath_provider = "ADVANCED_DATAPATH"

  # Private cluster: nodes have no external IPs and the control plane endpoint
  # is only reachable from private networks. Master global access lets every
  # region's private network (VPN/Interconnect spokes) reach the endpoint.
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = true
    master_ipv4_cidr_block  = var.master_ipv4_cidr_block

    master_global_access_config {
      enabled = true
    }
  }

  # Defense in depth: even on the private endpoint, only these CIDRs may talk
  # to the API server. Defaults to RFC 1918 space only.
  master_authorized_networks_config {
    dynamic "cidr_blocks" {
      for_each = var.master_authorized_networks
      content {
        cidr_block   = cidr_blocks.value.cidr_block
        display_name = cidr_blocks.value.display_name
      }
    }
  }

  # --- Security / identity ---------------------------------------------------
  # Workload Identity lets product teams' pods call Pub/Sub, Cloud Storage and
  # Cloud SQL as dedicated IAM service accounts — no node keys, no secrets in
  # the cluster.

  workload_identity_config {
    workload_pool = local.workload_pool
  }

  # --- Nodes -----------------------------------------------------------------
  # The default node pool is removed; capacity is managed by the dedicated
  # google_container_node_pool resource in node_pools.tf.

  remove_default_node_pool = true
  initial_node_count       = 1

  # --- Observability & add-ons ------------------------------------------------

  logging_config {
    enable_components = ["SYSTEM_COMPONENTS", "WORKLOADS"]
  }

  monitoring_config {
    enable_components = ["SYSTEM_COMPONENTS"]

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

    # NodeLocal DNSCache: fewer conntrack races and lower DNS latency for
    # chatty production workloads.
    dns_cache_config {
      enabled = true
    }
  }

  dynamic "notification_config" {
    for_each = local.upgrade_notifications_topic == null ? [] : [local.upgrade_notifications_topic]
    content {
      pubsub {
        enabled = true
        topic   = notification_config.value
      }
    }
  }

  # --- Ops -------------------------------------------------------------------

  resource_labels     = local.cluster_labels
  deletion_protection = var.deletion_protection

  lifecycle {
    # initial_node_count is only meaningful while bootstrapping the (removed)
    # default pool; never let drift on it churn the cluster.
    ignore_changes = [initial_node_count]
  }
}
