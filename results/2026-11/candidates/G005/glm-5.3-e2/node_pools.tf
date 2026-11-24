# ===========================================================================
# Node pools
# ===========================================================================

resource "google_container_node_pool" "this" {
  provider = google

  for_each = local.node_pools

  name     = each.key
  location = var.region
  cluster  = google_container_cluster.this.name

  autoscaling {
    min_node_count  = each.value.min_count
    max_node_count  = each.value.max_count
    location_policy = "BALANCED"
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  # Surge upgrades keep full capacity while nodes roll: one extra node is
  # added before an old one is drained, and no node is taken down before a
  # replacement is Ready.
  upgrade_settings {
    strategy        = "SURGE"
    max_surge       = 1
    max_unavailable = 0
  }

  node_config {
    machine_type = each.value.machine_type
    disk_size_gb = each.value.disk_size_gb
    disk_type    = each.value.disk_type
    image_type   = "COS_CONTAINERD"
    spot         = each.value.spot

    # Dedicated, least-privilege service account (see iam.tf). Broad
    # cloud-platform scope is intentional: access is governed by IAM roles
    # on this service account, not by legacy OAuth scopes.
    service_account = google_service_account.nodes.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]

    labels = each.value.labels

    # Kubernetes-style taints, e.g. to dedicate a pool to one team. The
    # variable takes Kubernetes spelling (NoSchedule/...); GKE's API spells
    # them NO_SCHEDULE/..., so they are mapped here.
    dynamic "taint" {
      for_each = { for index, taint in each.value.taints : format("%d", index) => taint }
      content {
        key    = taint.value.key
        value  = taint.value.value
        effect = local.taint_effects[taint.value.effect]
      }
    }

    # Nodes expose only the GKE metadata server, which is what makes
    # Workload Identity tokens flow to pods.
    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    # Image streaming: faster, more reliable pod startup for product teams.
    gcfs_config {
      enabled = true
    }
  }

  # Don't boot nodes before their service account's roles exist.
  depends_on = [google_project_iam_member.node_sa]
}
