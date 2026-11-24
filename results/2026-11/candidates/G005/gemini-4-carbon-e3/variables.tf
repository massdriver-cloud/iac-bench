# -----------------------------------------------------------------------------
# Required Cluster-Specific Inputs
# -----------------------------------------------------------------------------

variable "project_id" {
  description = "Google Cloud project ID hosting the environment VPC and this GKE cluster."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "project_id must be a valid Google Cloud project ID (6-30 lowercase letters, digits, or hyphens)."
  }
}

variable "cluster_name" {
  description = "Name of the GKE Standard cluster (unique within the project and region)."
  type        = string

  validation {
    condition     = can(regex("^[a-z]([a-z0-9-]{0,38}[a-z0-9])?$", var.cluster_name))
    error_message = "cluster_name must be 1-40 characters, start with a lowercase letter, contain only lowercase letters, numbers, or hyphens, and not end with a hyphen."
  }
}

variable "environment" {
  description = "Target environment ('staging' or 'prod'). Selects the network team's VPC ('apps-staging' or 'apps-prod') and regional GKE subnet ('<vpc>-gke-<region>')."
  type        = string

  validation {
    condition     = contains(["staging", "prod"], var.environment)
    error_message = "environment must be either 'staging' (uses VPC apps-staging) or 'prod' (uses VPC apps-prod)."
  }
}

variable "region" {
  description = "US Google Cloud region for the regional GKE cluster (e.g. 'us-central1', 'us-east1', 'us-east4', 'us-west1')."
  type        = string

  validation {
    condition     = can(regex("^us-[a-z]+[0-9]+$", var.region))
    error_message = "region must be a US Google Cloud region name (e.g. 'us-central1'), not a zone or non-US region."
  }
}

# -----------------------------------------------------------------------------
# Cluster Topology, Lifecycle & Operations
# -----------------------------------------------------------------------------

variable "description" {
  description = "Optional human-readable description attached to the GKE cluster."
  type        = string
  default     = null
}

variable "node_zones" {
  description = "Optional list of compute zones within var.region for node placement. When null, GKE automatically distributes nodes across 3 zones in the region."
  type        = list(string)
  default     = null

  validation {
    condition     = var.node_zones == null || length(coalesce(var.node_zones, [])) >= 2
    error_message = "node_zones must be null or specify at least 2 zones for multi-zone high availability."
  }
}

variable "release_channel" {
  description = "GKE release channel governing automatic Kubernetes version upgrades ('REGULAR' or 'STABLE')."
  type        = string
  default     = "REGULAR"

  validation {
    condition     = contains(["REGULAR", "STABLE"], var.release_channel)
    error_message = "release_channel must be 'REGULAR' or 'STABLE' for production-grade clusters."
  }
}

variable "deletion_protection" {
  description = "Whether OpenTofu/GKE prevents accidental cluster deletion. Set to false before intentionally destroying a cluster."
  type        = bool
  default     = true
}

variable "labels" {
  description = "Additional GCP resource labels applied to the cluster and node pools (keys and values must use lowercase letters, digits, underscores, or hyphens)."
  type        = map(string)
  default     = {}

  validation {
    condition = alltrue([
      for k, v in var.labels :
      can(regex("^[a-z][a-z0-9_-]{0,62}$", k)) && can(regex("^[a-z0-9_-]{0,63}$", v))
    ])
    error_message = "GCP label keys must start with a lowercase letter (max 63 chars) and values may contain only lowercase letters, digits, underscores, or hyphens (max 63 chars)."
  }
}

variable "maintenance_window" {
  description = "Recurring GKE maintenance window (RFC3339 timestamps and RFC5545 RRULE). Defaults to US weekend off-peak nights (Sat/Sun 04:00-10:00 UTC)."
  type = object({
    start_time = string
    end_time   = string
    recurrence = string
  })
  default = {
    start_time = "2025-01-04T04:00:00Z"
    end_time   = "2025-01-04T10:00:00Z"
    recurrence = "FREQ=WEEKLY;BYDAY=SA,SU"
  }
}

variable "maintenance_exclusions" {
  description = "Optional blackout windows during which automatic GKE upgrades are paused (e.g. peak traffic events)."
  type = map(object({
    start_time = string
    end_time   = string
    scope      = optional(string, "NO_MINOR_OR_NODE_UPGRADES")
  }))
  default = {}

  validation {
    condition = alltrue([
      for _, ex in var.maintenance_exclusions :
      contains(["NO_UPGRADES", "NO_MINOR_UPGRADES", "NO_MINOR_OR_NODE_UPGRADES"], ex.scope)
    ])
    error_message = "Each maintenance exclusion scope must be 'NO_UPGRADES', 'NO_MINOR_UPGRADES', or 'NO_MINOR_OR_NODE_UPGRADES'."
  }
}

# -----------------------------------------------------------------------------
# Networking & Control Plane Access
# -----------------------------------------------------------------------------

variable "enable_private_endpoint" {
  description = "When true, disables the external IP endpoint on the Kubernetes API server completely so it is reachable only from internal/peered networks. When false (default), external access is still blocked except for CIDRs listed in authorized_networks."
  type        = bool
  default     = false
}

variable "control_plane_cidr" {
  description = "Optional /28 RFC1918 CIDR block for legacy VPC-peered private control plane networking. Leave null (recommended) to use GKE Private Service Connect without consuming /28 peering ranges across clusters."
  type        = string
  default     = null

  validation {
    condition     = var.control_plane_cidr == null || (can(cidrhost(coalesce(var.control_plane_cidr, "172.16.0.0/28"), 0)) && endswith(coalesce(var.control_plane_cidr, "/28"), "/28"))
    error_message = "control_plane_cidr must be null or a valid IPv4 /28 CIDR block (e.g. '172.16.0.0/28')."
  }
}

variable "authorized_networks" {
  description = "List of external/internal CIDR blocks (such as corporate VPNs or CI/CD runners) permitted to reach the Kubernetes API server."
  type = list(object({
    cidr_block   = string
    display_name = string
  }))
  default = []

  validation {
    condition     = alltrue([for net in var.authorized_networks : can(cidrhost(net.cidr_block, 0))])
    error_message = "Every entry in authorized_networks must have a valid IPv4/IPv6 CIDR block."
  }
}

# -----------------------------------------------------------------------------
# Node Pools
# -----------------------------------------------------------------------------

variable "node_pools" {
  description = <<-EOT
    Map of managed GKE Standard node pools to create in the cluster.
    Each pool automatically spreads across zones in the region, uses Container-Optimized OS with containerd,
    enforces Shielded Nodes and GKE Metadata Server (Workload Identity), and runs under a dedicated least-privilege
    node service account. Note: min_nodes_per_zone and max_nodes_per_zone apply per zone (e.g. min 1 = 3 nodes across 3 zones).
  EOT
  type = map(object({
    machine_type       = optional(string, "n2-standard-4")
    disk_size_gb       = optional(number, 100)
    disk_type          = optional(string, "pd-balanced")
    min_nodes_per_zone = optional(number, 1)
    max_nodes_per_zone = optional(number, 10)
    max_pods_per_node  = optional(number, 64)
    spot               = optional(bool, false)
    image_streaming    = optional(bool, true)
    enable_gvnic       = optional(bool, true)
    labels             = optional(map(string), {})
    network_tags       = optional(list(string), [])
    max_surge          = optional(number, 1)
    max_unavailable    = optional(number, 0)
    node_zones         = optional(list(string), null)
    taints = optional(list(object({
      key    = string
      value  = string
      effect = string
    })), [])
  }))
  default = {
    general = {}
  }

  validation {
    condition     = length(var.node_pools) >= 1
    error_message = "At least one node pool must be defined in node_pools."
  }

  validation {
    condition = alltrue([
      for name, _ in var.node_pools :
      can(regex("^[a-z]([a-z0-9-]{0,38}[a-z0-9])?$", name))
    ])
    error_message = "Node pool names must be 1-40 characters, start with a lowercase letter, and contain only lowercase letters, digits, or hyphens."
  }

  validation {
    condition = alltrue([
      for _, pool in var.node_pools :
      pool.min_nodes_per_zone >= 0 &&
      pool.max_nodes_per_zone >= 1 &&
      pool.max_nodes_per_zone >= pool.min_nodes_per_zone &&
      pool.disk_size_gb >= 30 &&
      contains(["pd-standard", "pd-balanced", "pd-ssd", "hyperdisk-balanced"], pool.disk_type) &&
      pool.max_pods_per_node >= 8 &&
      pool.max_pods_per_node <= 110 &&
      (pool.max_surge + pool.max_unavailable) >= 1 &&
      pool.max_surge >= 0 &&
      pool.max_unavailable >= 0 &&
      alltrue([for t in pool.taints : contains(["NO_SCHEDULE", "PREFER_NO_SCHEDULE", "NO_EXECUTE"], t.effect)])
    ])
    error_message = "Invalid node_pools configuration: ensure max_nodes_per_zone >= min_nodes_per_zone >= 0 (max >= 1), disk_size_gb >= 30, valid disk_type, max_pods_per_node in 8..110, max_surge + max_unavailable >= 1, and taint effect in NO_SCHEDULE, PREFER_NO_SCHEDULE, or NO_EXECUTE."
  }
}

variable "autoscaling_profile" {
  description = "Cluster autoscaler bin-packing profile across managed node pools ('BALANCED' or 'OPTIMIZE_UTILIZATION')."
  type        = string
  default     = "BALANCED"

  validation {
    condition     = contains(["BALANCED", "OPTIMIZE_UTILIZATION"], var.autoscaling_profile)
    error_message = "autoscaling_profile must be 'BALANCED' or 'OPTIMIZE_UTILIZATION'."
  }
}

# -----------------------------------------------------------------------------
# Security, IAM & Google Cloud Service Integration
# -----------------------------------------------------------------------------

variable "rbac_security_group" {
  description = "Optional Google Groups for GKE RBAC group email (typically 'gke-security-groups@<domain>') enabling Kubernetes RoleBindings to Google Workspace groups."
  type        = string
  default     = null
}

variable "etcd_kms_key_id" {
  description = "Optional Cloud KMS CryptoKey resource ID ('projects/<project>/locations/<region>/keyRings/<ring>/cryptoKeys/<key>') for application-layer encryption of Kubernetes Secrets in etcd."
  type        = string
  default     = null
}

variable "enable_binary_authorization" {
  description = "Whether to enforce project-singleton Binary Authorization container image attestation policies on the cluster (requires binaryauthorization.googleapis.com)."
  type        = bool
  default     = false
}

variable "enable_secret_manager_addon" {
  description = "Whether to enable the GKE Secret Manager CSI driver add-on (requires secretmanager.googleapis.com enabled in the project)."
  type        = bool
  default     = false
}

variable "enable_backup_for_gke" {
  description = "Whether to enable the Backup for GKE agent add-on for cluster/PVC backups (requires gkebackup.googleapis.com enabled in the project)."
  type        = bool
  default     = false
}

variable "artifact_registry_projects" {
  description = "Optional additional Google Cloud project IDs from which cluster nodes are permitted to pull container images via Artifact Registry."
  type        = list(string)
  default     = []
}

variable "workload_identities" {
  description = <<-EOT
    Optional Workload Identity bindings connecting Kubernetes ServiceAccounts (namespace + name)
    to Google Cloud Service Accounts for keyless access to Cloud SQL, Pub/Sub, Cloud Storage, and other GCP services.
    When existing_gsa_email is null, the module creates a dedicated GCP Service Account and grants any listed project_roles.
  EOT
  type = map(object({
    namespace           = string
    k8s_service_account = string
    existing_gsa_email  = optional(string, null)
    project_roles       = optional(list(string), [])
    description         = optional(string, null)
  }))
  default = {}

  validation {
    condition = alltrue([
      for k, _ in var.workload_identities :
      can(regex("^[a-z][a-z0-9-]{0,28}[a-z0-9]$", k))
    ])
    error_message = "Keys in workload_identities must be 2-30 lowercase alphanumeric/hyphen characters."
  }
}

# -----------------------------------------------------------------------------
# Observability
# -----------------------------------------------------------------------------

variable "enable_managed_prometheus" {
  description = "Whether to enable Google Cloud Managed Service for Prometheus collection on the cluster."
  type        = bool
  default     = true
}

variable "logging_components" {
  description = "GKE components sending logs to Cloud Logging."
  type        = list(string)
  default     = ["SYSTEM_COMPONENTS", "WORKLOADS"]
}

variable "monitoring_components" {
  description = "GKE components exporting metrics to Cloud Monitoring."
  type        = list(string)
  default = [
    "SYSTEM_COMPONENTS",
    "APISERVER",
    "SCHEDULER",
    "CONTROLLER_MANAGER",
    "STORAGE",
    "HPA",
    "POD",
    "DAEMONSET",
    "DEPLOYMENT",
    "STATEFULSET",
    "KUBELET",
    "CADVISOR",
  ]
}
