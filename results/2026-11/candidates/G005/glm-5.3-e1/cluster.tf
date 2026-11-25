# -----------------------------------------------------------------------------
# Node identity: a dedicated, least-privilege service account per cluster
# -----------------------------------------------------------------------------
# Nodes never run as the project's default Compute Engine service account,
# which is typically far too powerful. The roles below are the minimum GKE
# needs: write logs and metrics, read images from Artifact Registry. Access to
# Google services used by workloads (Pub/Sub, Cloud Storage, Cloud SQL, ...) is
# granted to *workload* identities instead (see workload_identity.tf), never to
# the node identity.

resource "google_service_account" "nodes" {
  account_id   = "gke-${var.name}-nodes"
  display_name = "GKE node identity for cluster ${var.name} (${var.environment}/${var.region})"
}

resource "google_project_iam_member" "node_service_account" {
  for_each = toset(concat(
    [
      "roles/artifactregistry.reader",
      "roles/logging.logWriter",
      "roles/monitoring.metricWriter",
      "roles/monitoring.viewer",
      "roles/stackdriver.resourceMetadata.writer",
    ],
    var.additional_node_service_account_roles,
  ))

  project = var.project_id
  role    = each.key
  member  = "serviceAccount:${google_service_account.nodes.email}"
}

# -----------------------------------------------------------------------------
# The cluster
# -----------------------------------------------------------------------------
resource "google_container_cluster" "this" {
  name     = var.name
  location = var.region # a region, not a zone: control plane and nodes spread over the region's zones

  # These are production clusters shared by product teams: an accidental
  # `tofu destroy` must not be able to delete one.
  deletion_protection = var.deletion_protection

  # The network team owns one VPC per environment, with a ready-made GKE
  # subnet per US region. Names are derived, not retyped.
  network    = local.network
  subnetwork = local.subnetwork

  # VPC-native (alias IP) cluster: Pods and Services come out of the secondary
  # ranges "pods" and "services" the network team provisioned on the subnet.
  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  # Nodes are always private (no public IPs). By default the control plane
  # keeps a public endpoint restricted to master_authorized_networks, which is
  # what platform engineers use day to day; set enable_private_endpoint = true
  # when the team reaches the API server over the VPC instead.
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = var.enable_private_endpoint
    master_ipv4_cidr_block  = var.master_ipv4_cidr_block # null -> GKE picks a free /28

    # Allow the control plane's private IP to be reached from peered/shared
    # networks later, without a cluster rebuild.
    master_global_access_config {
      enabled = true
    }
  }

  master_authorized_networks_config {
    dynamic "cidr_blocks" {
      for_each = var.master_authorized_networks
      content {
        cidr_block   = cidr_blocks.value
        display_name = cidr_blocks.key
      }
    }
  }

  # Release channels own all versioning. The module never pins a Kubernetes
  # version: pinning drifts, channels don't, and channel upgrades respect the
  # maintenance window below.
  release_channel {
    channel = var.release_channel
  }

  # Nodes live in managed node pools (node_pools.tf); the pool that the
  # cluster resource itself would create is removed immediately. node_config
  # is still set so even that short-lived pool uses the dedicated node
  # identity rather than the project default account.
  remove_default_node_pool = true
  node_config {
    service_account = google_service_account.nodes.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]
  }

  # Kubernetes NetworkPolicy enforcement: namespaces belonging to different
  # product teams can isolate themselves from each other.
  network_policy {
    enabled = var.enable_network_policy
  }

  # Workload Identity: workloads in the cluster can impersonate Google
  # service accounts (Pub/Sub, Cloud Storage, Cloud SQL, ...) with no
  # exported keys. The Kubernetes->Google bindings themselves are declared in
  # var.workload_identity_bindings.
  workload_identity_config {
    workload_pool = local.workload_identity_pool
  }

  # Hardened control plane.
  enable_shielded_nodes = true

  # Cloud Logging and Monitoring. The monitoring component set is the one GKE
  # recommends for Managed Service for Prometheus, which multi-team clusters
  # rely on for per-namespace metrics.
  logging_config {
    enable_components = ["SYSTEM_COMPONENTS", "WORKLOADS"]
  }

  monitoring_config {
    enable_components = [
      "SYSTEM_COMPONENTS",
      "DEPLOYMENT",
      "STATEFULSET",
      "DAEMONSET",
      "HPA",
      "POD",
      "CADVISOR",
    ]
  }

  # One weekly maintenance window. Disruptive control plane work only happens
  # inside it; node upgrades are additionally rolled one node at a time (see
  # node_pools.tf).
  maintenance_policy {
    recurring_window {
      start_time = local.maintenance_start
      end_time   = local.maintenance_end
      recurrence = "FREQ=WEEKLY;BYDAY=${var.maintenance_window.day}"
    }
  }

  # RBAC Google Groups: when set, membership of the named Google Group decides
  # who can be bound to cluster-admin in RBAC, which is how access is usually
  # run for clusters shared across teams.
  dynamic "authenticator_groups_config" {
    for_each = var.authenticator_security_group == null ? [] : [var.authenticator_security_group]
    content {
      security_group = authenticator_groups_config.value
    }
  }

  # Optional CMEK for Kubernetes Secrets at rest.
  dynamic "database_encryption" {
    for_each = var.database_encryption_kms_key == null ? [] : [var.database_encryption_kms_key]
    content {
      state    = "ENCRYPTED"
      key_name = database_encryption.value
    }
  }

  # Gateway API: the shared-cluster story for ingress, where each product team
  # owns its own Gateway instead of annotating a shared LoadBalancer Service.
  dynamic "gateway_api_config" {
    for_each = var.enable_gateway_api ? [true] : []
    content {
      channel = "CHANNEL_STANDARD"
    }
  }

  # Labels on the cluster's underlying Google Cloud resources (visible in the
  # console and billing); node pools carry the same set (node_pools.tf).
  resource_labels = local.labels
}
