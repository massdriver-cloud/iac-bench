variable "project_id" {
  description = "Existing Google Cloud project containing both the cluster and the environment VPC."
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "Supply a valid Google Cloud project ID, not its display name or number."
  }
}

variable "cluster_name" {
  description = "Unique cluster name in this project/region; also used to name the dedicated node service account."
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,22}[a-z0-9]$", var.cluster_name))
    error_message = "Use 2-24 lowercase letters, digits or hyphens, starting with a letter and ending in a letter or digit."
  }
}

variable "environment" {
  description = "Selects the existing apps-staging or apps-prod VPC."
  type        = string
  validation {
    condition     = contains(["staging", "prod"], var.environment)
    error_message = "environment must be staging or prod."
  }
}

variable "region" {
  description = "US region containing the pre-created <vpc>-gke-<region> subnet. GKE uses three zones in this region by default."
  type        = string
  default     = "us-central1"
  validation {
    condition     = can(regex("^us-[a-z]+[0-9]+$", var.region))
    error_message = "Select a US region, for example us-central1."
  }
}

variable "master_ipv4_cidr_block" {
  description = "Unused, non-overlapping RFC1918 /28 for the private control plane. Coordinate with the network team; cannot overlap VPC, secondary, peered, or on-premises networks."
  type        = string
  validation {
    condition = can(cidrnetmask(var.master_ipv4_cidr_block)) && can(regex("/28$", var.master_ipv4_cidr_block)) && (
      can(regex("^10\\.", var.master_ipv4_cidr_block)) ||
      can(regex("^192\\.168\\.", var.master_ipv4_cidr_block)) ||
      can(regex("^172\\.(1[6-9]|2[0-9]|3[01])\\.", var.master_ipv4_cidr_block))
    )
    error_message = "The control-plane range must be an RFC1918 IPv4 /28."
  }
}

variable "enable_public_endpoint" {
  description = "Opt in to a public control-plane endpoint restricted to authorized_networks. Nodes always remain private."
  type        = bool
  default     = false
}

variable "authorized_networks" {
  description = "Trusted administrator/VPN source CIDRs allowed at the control plane (including the private endpoint). Empty means only GKE's automatically allowed cluster sources; provide your management ranges for kubectl access. Never use a default route."
  type = list(object({
    display_name = string
    cidr_block   = string
  }))
  default = []
  validation {
    condition = length(var.authorized_networks) <= 100 && alltrue([
      for network in var.authorized_networks : can(cidrnetmask(network.cidr_block)) && try(tonumber(split("/", network.cidr_block)[1]) >= 8, false)
    ])
    error_message = "Supply at most 100 IPv4 CIDRs with prefixes /8 or narrower; use only your trusted management networks."
  }
}

variable "node_locations" {
  description = "Optional explicit zone selection. If set, supply at least three different zones in region. Otherwise GKE chooses three zones."
  type        = list(string)
  default     = null
  validation {
    condition     = var.node_locations == null ? true : length(distinct(var.node_locations)) >= 3
    error_message = "Regional resilience requires at least three distinct node zones."
  }
}

variable "node_pools" {
  description = "On-demand, shielded, Workload Identity-enabled pools. Min/max counts are TOTAL across zones, not per-zone. Every pool keeps at least three nodes; initial size is one node per selected zone. Budget for max_nodes plus surge nodes in each zone."
  type = map(object({
    machine_type      = optional(string, "e2-standard-4")
    disk_size_gb      = optional(number, 100)
    disk_type         = optional(string, "pd-balanced")
    min_nodes         = optional(number, 3)
    max_nodes         = optional(number, 12)
    max_pods_per_node = optional(number, 64)
    labels            = optional(map(string), {})
    taints = optional(list(object({
      key    = string
      value  = string
      effect = string
    })), [])
  }))
  default = { general = {} }
  validation {
    condition = length(var.node_pools) > 0 && alltrue([
      for name, pool in var.node_pools :
      can(regex("^[a-z][a-z0-9-]{0,38}[a-z0-9]$", name)) &&
      pool.min_nodes >= 3 && pool.min_nodes == floor(pool.min_nodes) &&
      pool.max_nodes >= pool.min_nodes && pool.max_nodes == floor(pool.max_nodes) &&
      pool.disk_size_gb >= 50 && pool.disk_size_gb == floor(pool.disk_size_gb) &&
      contains(["pd-standard", "pd-balanced", "pd-ssd"], pool.disk_type) &&
      contains([8, 16, 32, 64, 128, 256], pool.max_pods_per_node) &&
      alltrue([for taint in pool.taints : contains(["NO_SCHEDULE", "PREFER_NO_SCHEDULE", "NO_EXECUTE"], taint.effect)])
    ])
    error_message = "Pools need valid 2-40 character names, integer total min >= 3, max >= min, integer disks >= 50 GiB, a supported disk type, power-of-two max pods 8-256, and valid taint effects."
  }
  validation {
    condition     = anytrue([for pool in values(var.node_pools) : length(pool.taints) == 0])
    error_message = "Keep at least one untainted pool for general and system workloads."
  }
}

variable "release_channel" {
  description = "Managed upgrade channel. STABLE favors production soak time; REGULAR is available for earlier features. Unmanaged versions are intentionally unsupported."
  type        = string
  default     = "STABLE"
  validation {
    condition     = contains(["STABLE", "REGULAR"], var.release_channel)
    error_message = "Use STABLE or REGULAR."
  }
}

variable "maintenance_window" {
  description = "Recurring UTC upgrade window. Default is six hours every day (meets GKE's >=48h per rolling 32 days, in >=4h blocks). Custom recurrence must also meet GKE's availability rules."
  type = object({
    start_time = string
    end_time   = string
    recurrence = string
  })
  default = {
    start_time = "2025-01-01T06:00:00Z"
    end_time   = "2025-01-01T12:00:00Z"
    recurrence = "FREQ=DAILY"
  }
  validation {
    condition     = can(timecmp(var.maintenance_window.end_time, timeadd(var.maintenance_window.start_time, "4h"))) ? timecmp(var.maintenance_window.end_time, timeadd(var.maintenance_window.start_time, "4h")) >= 0 : false
    error_message = "Use RFC3339 timestamps defining a maintenance window of at least four hours."
  }
}

variable "deletion_protection" {
  description = "Prevents accidental cluster destruction. Explicitly set false and apply before intentional destroy."
  type        = bool
  default     = true
}

variable "resource_labels" {
  description = "Additional GCP cluster and node labels. Managed environment and managed-by labels take precedence."
  type        = map(string)
  default     = {}
}

variable "artifact_registry_repositories" {
  description = "Repositories from which nodes may pull private images. Grants reader on ONLY these repositories, never project-wide. Map keys are stable identifiers; project_id may refer to another project."
  type = map(object({
    project_id = string
    location   = string
    repository = string
  }))
  default = {}
}

variable "workload_identities" {
  description = "Optional keyless GSA identities for Kubernetes service accounts. Map key becomes a GSA account ID; project_roles grants additive roles in the cluster project. Prefer service-specific IAM outside this module for bucket/topic-level scope. Kubernetes service accounts/annotations are deployed separately."
  type = map(object({
    namespace                  = string
    kubernetes_service_account = string
    project_roles              = optional(set(string), [])
  }))
  default = {}
  validation {
    condition = alltrue([
      for account, identity in var.workload_identities :
      can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", account)) &&
      can(regex("^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$", identity.namespace)) &&
      can(regex("^[a-z0-9]([a-z0-9.-]{0,251}[a-z0-9])?$", identity.kubernetes_service_account)) &&
      alltrue([for role in identity.project_roles : !contains(["roles/owner", "roles/editor", "roles/viewer"], role)])
    ])
    error_message = "Use valid GSA account IDs (6-30 characters), Kubernetes namespace/service account names, and non-basic least-privilege roles."
  }
}
