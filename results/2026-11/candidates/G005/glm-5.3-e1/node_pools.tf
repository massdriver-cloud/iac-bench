# -----------------------------------------------------------------------------
# Node pools
# -----------------------------------------------------------------------------
# One managed node pool per entry of var.node_pools; the map key is the pool
# name. Node counts are PER ZONE: on a regional cluster the default "general"
# pool (min_count 2) gives 6 nodes spread over the region's three zones.

resource "google_container_node_pool" "this" {
  for_each = var.node_pools

  name     = each.key
  cluster  = google_container_cluster.this.name
  location = var.region

  # null -> GKE spreads the pool over every zone in the region.
  node_locations = each.value.node_locations

  # null -> GKE default (110 Pods per node), which keeps the pods secondary
  # range the network team sized in charge of address exhaustion.
  max_pods_per_node = each.value.max_pods_per_node

  autoscaling {
    min_node_count = each.value.min_count
    max_node_count = each.value.max_count
  }

  # The release channel owns versions; pools just repair and upgrade
  # themselves inside the maintenance window.
  management {
    auto_repair  = true
    auto_upgrade = true
  }

  # Replace nodes one at a time (max_unavailable 0): on a cluster shared by
  # several product teams an upgrade must never take multiple nodes out of
  # service simultaneously.
  upgrade_settings {
    max_surge       = 1
    max_unavailable = 0
  }

  node_config {
    machine_type = each.value.machine_type
    disk_type    = each.value.disk_type
    disk_size_gb = each.value.disk_size_gb
    image_type   = each.value.image_type
    spot         = each.value.spot
    preemptible  = each.value.preemptible

    service_account = google_service_account.nodes.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]

    # Every pool carries pool = <name> so product teams can pin workloads to
    # their pool with a nodeSelector, plus the shared cluster labels.
    labels = merge({ "pool" = each.key }, local.labels, each.value.labels)

    # Legacy metadata endpoints are a known node-metadata attack surface.
    metadata = {
      disable-legacy-endpoints = "true"
    }

    # Shielded VMs on every node.
    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    # Nodes expose GKE's metadata server only: the node identity cannot be
    # read from inside a Pod, which is what makes Workload Identity safe.
    workload_metadata_config {
      mode = "GKE_METADATA"
    }
  }

  # Nodes only come up once the node identity actually holds its roles.
  depends_on = [google_project_iam_member.node_service_account]
}
