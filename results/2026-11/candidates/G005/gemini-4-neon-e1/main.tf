# ------------------------------------------------------------------------------
# GKE Standard Regional Production Cluster
# ------------------------------------------------------------------------------

resource "google_container_cluster" "this" {
  project  = var.project_id
  name     = var.cluster_name
  location = var.region

  # Attach to the network team's pre-created environment VPC and regional GKE subnet.
  network         = local.network_self_link
  subnetwork      = local.subnetwork_self_link
  networking_mode = "VPC_NATIVE"

  # Standard GKE best practice: remove the default node pool immediately after
  # cluster creation and manage dedicated node pools independently (node_pools.tf).
  remove_default_node_pool = true
  initial_node_count       = 1

  deletion_protection       = var.deletion_protection
  default_max_pods_per_node = var.default_max_pods_per_node

  # Dataplane V2 (eBPF/Cilium): native Kubernetes NetworkPolicy + Clusterwide
  # NetworkPolicy enforcement for isolating product-team namespaces, plus
  # transparent inter-node WireGuard encryption.
  datapath_provider                        = "ADVANCED_DATAPATH"
  enable_cilium_clusterwide_network_policy = true
  enable_intranode_visibility              = true
  in_transit_encryption_config             = "IN_TRANSIT_ENCRYPTION_INTER_NODE_TRANSPARENT"

  # Enable Shielded GKE Nodes and scalable L4 Internal Load Balancer subsetting.
  enable_shielded_nodes    = true
  enable_l4_ilb_subsetting = true

  resource_labels = local.common_labels

  # Use the network team's pre-created secondary IP ranges for pods and services.
  ip_allocation_policy {
    cluster_secondary_range_name  = local.pods_secondary_range_name
    services_secondary_range_name = local.services_secondary_range_name
  }

  # Private nodes: worker nodes receive only RFC1918 private IPs (no public IPs).
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = var.enable_private_endpoint
    master_ipv4_cidr_block  = var.control_plane_cidr
  }

  # Fail-closed control plane access: deny external IPs unless explicitly listed.
  master_authorized_networks_config {
    gcp_public_cidrs_access_enabled = var.gcp_public_cidrs_access_enabled

    dynamic "cidr_blocks" {
      for_each = var.authorized_networks
      content {
        cidr_block   = cidr_blocks.value.cidr_block
        display_name = cidr_blocks.value.display_name
      }
    }
  }

  # Disable legacy static client certificates and restrict anonymous API access.
  master_auth {
    client_certificate_config {
      issue_client_certificate = false
    }
  }

  anonymous_authentication_config {
    mode = "LIMITED"
  }

  # Workload Identity Federation: enables product-team pods to authenticate
  # directly to Pub/Sub, Cloud Storage, Cloud SQL, etc. without static keys.
  workload_identity_config {
    workload_pool = local.workload_identity_pool
  }

  # Automated Kubernetes patch & upgrade lifecycle.
  release_channel {
    channel = var.release_channel
  }

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

  # Cloud DNS for GKE eliminates kube-dns scaling bottlenecks in shared clusters.
  dns_config {
    cluster_dns       = "CLOUD_DNS"
    cluster_dns_scope = "CLUSTER_SCOPE"
  }

  # Production addons including GCE PD CSI and Cloud Storage FUSE CSI drivers.
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
  }

  # Standard Kubernetes Gateway API support for multi-team traffic routing.
  gateway_api_config {
    channel = "CHANNEL_STANDARD"
  }

  vertical_pod_autoscaling {
    enabled = true
  }

  cluster_autoscaling {
    autoscaling_profile = var.autoscaling_profile
  }

  # Multi-team cost allocation by namespace and Kubernetes labels.
  cost_management_config {
    enabled = true
  }

  # Continuous security posture auditing and basic workload vulnerability scanning.
  security_posture_config {
    mode               = "BASIC"
    vulnerability_mode = "VULNERABILITY_BASIC"
  }

  logging_config {
    enable_components = var.logging_components
  }

  monitoring_config {
    enable_components = var.monitoring_components

    managed_prometheus {
      enabled = var.enable_managed_prometheus
    }

    advanced_datapath_observability_config {
      enable_metrics = true
      enable_relay   = false
    }
  }

  # Hardened configuration for the transient bootstrap default node pool so that
  # even initial cluster creation never uses the Compute Engine default SA or
  # unshielded instances.
  node_config {
    service_account = google_service_account.nodes.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]

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
  }

  # Optional: Google Groups for Kubernetes RBAC across product teams.
  dynamic "authenticator_groups_config" {
    for_each = var.rbac_security_group != null ? [var.rbac_security_group] : []
    content {
      security_group = authenticator_groups_config.value
    }
  }

  # Optional: Customer-managed encryption (CMEK) for Kubernetes Secrets in etcd.
  dynamic "database_encryption" {
    for_each = var.database_encryption_kms_key != null ? [var.database_encryption_kms_key] : []
    content {
      state    = "ENCRYPTED"
      key_name = database_encryption.value
    }
  }

  # Optional: Enforce Binary Authorization policy on container images.
  dynamic "binary_authorization" {
    for_each = var.enable_binary_authorization ? [1] : []
    content {
      evaluation_mode = "PROJECT_SINGLETON_POLICY_ENFORCE"
    }
  }

  # Optional: Publish GKE upgrade & security bulletin notifications to Pub/Sub.
  dynamic "notification_config" {
    for_each = var.notification_pubsub_topic != null ? [var.notification_pubsub_topic] : []
    content {
      pubsub {
        enabled = true
        topic   = notification_config.value
      }
    }
  }

  lifecycle {
    ignore_changes = [
      initial_node_count,
      node_config,
    ]
  }

  depends_on = [google_project_iam_member.node_sa_roles]
}

# ------------------------------------------------------------------------------
# Optional Admission Webhook Firewall Rule (Private Clusters)
# ------------------------------------------------------------------------------
# GKE automatically permits control-plane -> node traffic on TCP 443 and 10250.
# When platform teams install admission controllers (e.g., cert-manager, Kyverno,
# Gatekeeper, Istio) listening on custom webhook ports, this rule allows the
# control plane CIDR to reach only this cluster's worker nodes on those ports.

resource "google_compute_firewall" "control_plane_webhooks" {
  count = length(var.control_plane_webhook_ports) > 0 ? 1 : 0

  project     = var.project_id
  name        = "gke-${var.cluster_name}-webhooks"
  network     = local.network_self_link
  direction   = "INGRESS"
  description = "Allow GKE control plane to call Kubernetes admission webhooks on ${var.cluster_name} worker nodes."

  source_ranges = [var.control_plane_cidr]
  target_tags   = [local.cluster_node_tag]

  allow {
    protocol = "tcp"
    ports    = var.control_plane_webhook_ports
  }
}
