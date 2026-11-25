# ============================================================================
# Required inputs — the platform team fills these in for each cluster.
# ============================================================================

variable "project_id" {
  type        = string
  nullable    = false
  description = "ID of the Google Cloud project that owns the cluster. The cluster lives in the same project as the environment VPC (apps-staging / apps-prod)."

  validation {
    condition     = length(trimspace(var.project_id)) > 0
    error_message = "project_id must not be empty."
  }
}

variable "region" {
  type        = string
  nullable    = false
  description = <<-EOT
    Region the cluster is deployed in, e.g. "us-central1".

    The module creates a regional cluster: the control plane is replicated
    across zones of this region and node pools span those zones, so a
    single-zone outage does not take the cluster down.
  EOT

  validation {
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]$", var.region))
    error_message = "region must be a valid Google Cloud region name, e.g. \"us-central1\"."
  }
}

variable "cluster_name" {
  type        = string
  nullable    = false
  description = "Name of the cluster. Must be unique within the project and region: lowercase letters, digits and dashes, starting with a letter, at most 40 characters."

  validation {
    condition     = can(regex("^[a-z]([a-z0-9-]{0,38}[a-z0-9])?$", var.cluster_name))
    error_message = "cluster_name must be a valid GKE cluster name: lowercase letters, digits and dashes, starting with a letter, at most 40 characters."
  }
}

variable "network" {
  type        = string
  nullable    = false
  description = <<-EOT
    Name (or self-link) of the VPC the cluster is placed in, e.g. "apps-prod".

    The VPC is created and owned by the network team; the module only
    references it. By convention the network team has already created a
    subnetwork named "<vpc>-gke-<region>" with secondary ranges "pods" and
    "services" in every region; override `subnetwork` only if a given
    cluster deviates from that convention.
  EOT

  validation {
    condition     = length(trimspace(var.network)) > 0
    error_message = "network must not be empty."
  }
}

# ============================================================================
# Networking
# ============================================================================

variable "subnetwork" {
  type        = string
  default     = null
  description = "Name (or self-link) of the subnetwork for cluster nodes. Defaults to \"<network>-gke-<region>\", following the network team's naming convention."
}

variable "pods_secondary_range_name" {
  type        = string
  default     = "pods"
  description = "Name of the subnetwork secondary range used for Pod IPs. Matches the range name the network team creates on every GKE subnetwork."
}

variable "services_secondary_range_name" {
  type        = string
  default     = "services"
  description = "Name of the subnetwork secondary range used for Service (ClusterIP) IPs. Matches the range name the network team creates on every GKE subnetwork."
}

variable "enable_private_nodes" {
  type        = bool
  default     = true
  description = <<-EOT
    Give nodes only internal RFC1918 IPs (no public IPs). Keep this enabled
    for production.

    Note: the subnetwork must have Private Google Access (or a NAT path) so
    nodes can reach Google APIs and pull images — the network team owns that
    subnet setting.
  EOT
}

variable "enable_private_endpoint" {
  type        = bool
  default     = false
  description = <<-EOT
    Disable the public IP of the control-plane endpoint.

    When false (default) the endpoint is public; restrict it with
    `master_authorized_networks`. When true, the API server is only reachable
    from inside the VPC and you must run tofu/kubectl from a network with
    VPC access.
  EOT
}

variable "master_ipv4_cidr" {
  type        = string
  default     = "172.16.0.0/28"
  description = <<-EOT
    RFC1918 /28 range used for the control-plane VPC peering (required when
    nodes or the endpoint are private). It MUST be different for every
    cluster in the same VPC — allocate one /28 per cluster and override this
    default for the second and subsequent clusters in a VPC.
  EOT

  validation {
    condition     = can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}/28$", var.master_ipv4_cidr))
    error_message = "master_ipv4_cidr must be an IPv4 /28 CIDR, e.g. \"172.16.0.0/28\"."
  }
}

variable "master_authorized_networks" {
  type = list(object({
    cidr_block   = string
    display_name = optional(string, "")
  }))
  default     = []
  description = <<-EOT
    CIDRs allowed to reach the public control-plane endpoint (ignored when
    `enable_private_endpoint` is true). Empty means the endpoint is reachable
    from any IP — authentication is still required, but restricting this is
    recommended for production, e.g. to office and CI egress ranges.
  EOT
}

variable "node_locations" {
  type        = list(string)
  default     = []
  description = "Zones of the region to run control-plane instances and nodes in. Defaults to all zones of `region`, which is the right choice for production resilience."
}

# ============================================================================
# Cluster lifecycle and upgrades
# ============================================================================

variable "release_channel" {
  type        = string
  default     = "REGULAR"
  description = "GKE release channel that controls how quickly the control plane and nodes are upgraded: RAPID, REGULAR or STABLE. REGULAR is the recommended balance for production."

  validation {
    condition     = contains(["RAPID", "REGULAR", "STABLE"], var.release_channel)
    error_message = "release_channel must be one of RAPID, REGULAR or STABLE."
  }
}

variable "maintenance_start_time" {
  type        = string
  default     = "03:00"
  description = "Start of the daily maintenance window in UTC (HH:MM). GKE only performs disruptive control-plane and node upgrades inside this window. Default 03:00 UTC."

  validation {
    condition     = can(regex("^([01][0-9]|2[0-3]):[0-5][0-9]$", var.maintenance_start_time))
    error_message = "maintenance_start_time must be in 24h HH:MM format (UTC), e.g. \"03:00\"."
  }
}

variable "deletion_protection" {
  type        = bool
  default     = true
  description = "Prevent the cluster from being deleted (tofu destroy or API) until explicitly disabled. Keep true for production clusters."
}

variable "labels" {
  type        = map(string)
  default     = {}
  description = "GCP labels applied to the cluster and to module-created resources (e.g. the upgrade-notifications topic). Keys and values must be valid GCP label strings (lowercase letters, digits, '_' and '-')."
}

# ============================================================================
# Security
# ============================================================================

variable "enable_binary_authorization" {
  type        = bool
  default     = false
  description = "Enforce Binary Authorization so only attested container images can be deployed. Only enable once a project-wide Binary Authorization policy with attestors is in place, otherwise deployments will be rejected."
}

variable "rbac_security_group" {
  type        = string
  default     = null
  description = "Optional Google Workspace group that enables Google Groups for RBAC, e.g. \"gke-security-groups@example.com\". The group must exist and follow GKE's naming requirements (gke-security-groups@<domain>)."
}

variable "database_encryption_key" {
  type        = string
  default     = null
  description = "Optional Cloud KMS crypto key resource ID (projects/.../locations/.../keyRings/.../cryptoKeys/...) for application-layer encryption of Kubernetes Secrets. The key must already exist; the module grants the GKE service agent encrypter/decrypter on it."
}

# ============================================================================
# Node pools
# ============================================================================

variable "node_pools" {
  type = map(object({
    machine_type   = optional(string, "e2-standard-4")
    disk_size_gb   = optional(number, 100)
    disk_type      = optional(string, "pd-ssd")
    image_type     = optional(string, "COS_CONTAINERD")
    spot           = optional(bool, false)
    min_count      = optional(number, 1)
    max_count      = optional(number, 6)
    node_locations = optional(list(string), null)
    labels         = optional(map(string), {})
    tags           = optional(list(string), [])
    taints = optional(list(object({
      key    = string
      value  = string
      effect = string
    })), [])
  }))
  default = {
    primary = {}
  }
  description = <<-EOT
    Node pools for the cluster, keyed by pool name. The default creates one
    pool named "primary" (e2-standard-4, autoscaling 1-6 nodes per zone).

    Every pool is hardened by the module: COS_CONTAINERD image, shielded
    nodes with secure boot and integrity monitoring, Workload Identity
    (GKE_METADATA), gVNIC, image streaming, a dedicated least-privilege node
    service account, surge upgrades (max_surge=1, max_unavailable=0), and
    auto-repair/auto-upgrade.

    Attributes (all optional):
      machine_type   - GCE machine type (default "e2-standard-4").
      disk_size_gb   - Boot disk size in GB (default 100).
      disk_type      - Boot disk type: pd-standard | pd-ssd | pd-balanced (default "pd-ssd").
      image_type     - Node image (default "COS_CONTAINERD").
      spot           - Use Spot VMs (default false; not for pools serving latency-sensitive prod traffic).
      min_count      - Autoscaler floor, PER ZONE (default 1; with 3 zones that is 3 nodes minimum).
      max_count      - Autoscaler ceiling, PER ZONE (default 6).
      node_locations - Zones for this pool; defaults to the cluster's zones.
      labels         - Kubernetes node labels for this pool.
      tags           - GCE network tags on the nodes.
      taints         - Kubernetes node taints: list of { key, value, effect } with effect one of
                       NO_SCHEDULE, PREFER_NO_SCHEDULE, NO_EXECUTE.

    Example:
      node_pools = {
        primary = {
          machine_type = "e2-standard-4"
          min_count    = 1
          max_count    = 6
        }
        batch = {
          machine_type = "c2-standard-8"
          min_count    = 0
          max_count    = 20
          spot         = true
          taints       = [{ key = "workload", value = "batch", effect = "NO_SCHEDULE" }]
        }
      }
  EOT

  validation {
    condition     = length(var.node_pools) > 0
    error_message = "At least one node pool is required."
  }

  validation {
    condition     = alltrue([for name, _ in var.node_pools : can(regex("^[a-z0-9]([a-z0-9-]{0,38}[a-z0-9])?$", name))])
    error_message = "Node pool names must be lowercase letters, digits and dashes, starting with a letter or digit, at most 40 characters."
  }

  validation {
    condition     = alltrue([for _, pool in var.node_pools : pool.min_count >= 0 && pool.max_count > 0 && pool.max_count >= pool.min_count])
    error_message = "Each node pool must have max_count >= min_count >= 0 and max_count > 0."
  }

  validation {
    condition     = alltrue(flatten([for _, pool in var.node_pools : [for t in pool.taints : contains(["NO_SCHEDULE", "PREFER_NO_SCHEDULE", "NO_EXECUTE"], t.effect)]]))
    error_message = "Taint effect must be one of NO_SCHEDULE, PREFER_NO_SCHEDULE or NO_EXECUTE."
  }
}

variable "node_service_account_email" {
  type        = string
  default     = null
  description = "Optional existing service account email to use as the node identity. When null (default) the module creates a dedicated least-privilege service account per cluster and grants it the roles in `node_service_account_roles`."
}

variable "node_service_account_roles" {
  type = list(string)
  default = [
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/monitoring.viewer",
    "roles/stackdriver.resourceMetadata.writer",
    "roles/artifactregistry.reader",
  ]
  description = "Project roles granted to the module-created node service account. The defaults are the documented minimum for GKE nodes plus read access to Artifact Registry in the same project (for pulling images). Workloads should never rely on the node identity — they use Workload Identity instead."
}

# ============================================================================
# Observability
# ============================================================================

variable "logging_enabled_components" {
  type        = list(string)
  default     = ["SYSTEM_COMPONENTS", "WORKLOADS"]
  description = "GKE logging components to enable. Valid values: SYSTEM_COMPONENTS, WORKLOADS, APISERVER, SCHEDULER, CONTROLLER_MANAGER."
}

variable "monitoring_enabled_components" {
  type        = list(string)
  default     = ["SYSTEM_COMPONENTS"]
  description = "GKE Cloud Monitoring components to enable. Valid values: SYSTEM_COMPONENTS, APISERVER, SCHEDULER, CONTROLLER_MANAGER, STORAGE, HPA, POD, DAEMONSET, DEPLOYMENT, STATEFULSET, KUBELET, CADVISOR, DCGM. Enabling control-plane components beyond SYSTEM_COMPONENTS increases metric costs."
}

variable "enable_managed_prometheus" {
  type        = bool
  default     = true
  description = "Enable Google Cloud Managed Service for Prometheus collection for the cluster."
}

# ============================================================================
# Features
# ============================================================================

variable "enable_cost_allocation" {
  type        = bool
  default     = true
  description = "Enable GKE cost allocation, surfacing cluster usage and cost by namespace and label in Cloud Billing. Essential for a cluster shared by several product teams."
}

variable "enable_vertical_pod_autoscaling" {
  type        = bool
  default     = true
  description = "Enable the Vertical Pod Autoscaler so teams get right-sizing recommendations for their workloads."
}

variable "enable_gcs_fuse_csi_driver" {
  type        = bool
  default     = true
  description = "Enable the Cloud Storage FUSE CSI driver so workloads can mount Cloud Storage buckets as volumes (authenticates via Workload Identity)."
}

variable "enable_backup_agent" {
  type        = bool
  default     = true
  description = "Install the Backup for GKE agent so the platform team can protect cluster workloads with Backup for GKE plans."
}

variable "enable_upgrade_notifications" {
  type        = bool
  default     = false
  description = "Create a Pub/Sub topic named \"<cluster>-gke-upgrades\" and publish cluster upgrade and security-bulletin events to it. Requires the Pub/Sub API (pubsub.googleapis.com) to be enabled in the project."
}
