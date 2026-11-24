resource "google_container_cluster" "cluster" {
  name     = var.cluster_name
  location = var.region
  project  = var.project_id

  network    = data.google_compute_network.network.self_link
  subnetwork = data.google_compute_subnetwork.gke_subnet.self_link

  # The module owns resilience + upgrades; individual clusters only set sizing/tags.
  deletion_protection = true

  # No default node pool: nodes come from the managed pools below. This is the
  # modern "empty default pool" idiom (replaces remove_default_node_pool).
  initial_node_count = 0

  enable_intranode_visibility = true

  # VPC-native addressing using the network team's secondary ranges.
  networking_mode = "VPC_NATIVE"
  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
    stack_type                    = "IPV4"
  }

  release_channel {
    channel = var.release_channel
  }

  # Keep nodes off the public internet; control plane keeps a public endpoint
  # restricted to the authorized networks configured per cluster.
  private_cluster_config {
    enable_private_nodes    = var.enable_private_nodes
    enable_private_endpoint = false
    master_ipv4_cidr_block  = var.master_ipv4_cidr_block
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

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  binary_authorization {
    evaluation_mode = var.enable_binary_authorization ? "PROJECT_SINGLETON_POLICY_ENFORCE" : "DISABLED"
  }

  network_policy {
    enabled  = true
    provider = "CALICO"
  }

  vertical_pod_autoscaling {
    enabled = true
  }

  monitoring_config {
    enable_components = ["SYSTEM_COMPONENTS", "WORKLOADS"]
  }

  logging_config {
    enable_components = ["SYSTEM_COMPONENTS", "WORKLOADS"]
  }

  # Automated, user-auditable upgrades. Same recurring maintenance window across
  # clusters so upgrades are predictable for the team.
  maintenance_policy {
    recurring_window {
      start_time = "2024-01-01T09:00:00Z"
      end_time   = "2024-01-01T17:00:00Z"
      recurrence = "RRULE:FREQ=WEEKLY;BYDAY=TU,TH"
    }
  }

  depends_on = [
    google_project_iam_member.node_sa_roles,
    google_service_account_iam_member.node_workload_identity_user,
  ]
}