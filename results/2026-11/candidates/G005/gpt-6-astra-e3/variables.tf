variable "project_id" {
  description = "Existing project that contains the environment VPC and subnet."
  type        = string
  nullable    = false
}

variable "cluster_name" {
  description = "Unique cluster name within the project (also used for project-wide service account names)."
  type        = string
  nullable    = false
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,23}[a-z0-9]$", var.cluster_name))
    error_message = "Use 2-25 lowercase letters, digits or hyphens, starting with a letter and ending with a letter/digit."
  }
}

variable "environment" {
  description = "Selects the network team's apps-staging or apps-prod VPC."
  type        = string
  nullable    = false
  validation {
    condition     = contains(["staging", "prod"], var.environment)
    error_message = "environment must be staging or prod."
  }
}

variable "region" {
  description = "US GCP region with an existing <vpc>-gke-<region> subnet and pods/services secondary ranges."
  type        = string
  nullable    = false
  validation {
    condition     = can(regex("^us-[a-z]+[0-9]+$", var.region))
    error_message = "Choose a US region, for example us-central1."
  }
}

variable "master_ipv4_cidr_block" {
  description = "Dedicated, unused RFC1918 /28 for the control plane. Must not overlap any subnet, secondary range, peer or on-prem route; allocate uniquely per cluster."
  type        = string
  nullable    = false
  validation {
    condition = can(cidrnetmask(var.master_ipv4_cidr_block)) && can(regex("/28$", var.master_ipv4_cidr_block)) && (
      can(regex("^10\\.", var.master_ipv4_cidr_block)) ||
      can(regex("^192\\.168\\.", var.master_ipv4_cidr_block)) ||
      can(regex("^172\\.(1[6-9]|2[0-9]|3[01])\\.", var.master_ipv4_cidr_block))
    )
    error_message = "Supply an unused RFC1918 IPv4 /28."
  }
}

variable "private_endpoint" {
  description = "Keep the Kubernetes API private. Set false only for a deliberate allowlisted public API endpoint; nodes always stay private."
  type        = bool
  default     = true
  nullable    = false
}

variable "authorized_networks" {
  description = "Required trusted IPv4 sources for Kubernetes API access, including private clients. Use the source ranges as observed by the control plane after any NAT. GKE retains implicit node/pod access."
  type = list(object({
    name = string
    cidr = string
  }))
  nullable = false
  validation {
    condition = length(var.authorized_networks) >= 1 && length(var.authorized_networks) <= 50 && alltrue([
      for network in var.authorized_networks : can(cidrnetmask(network.cidr)) && try(tonumber(split("/", network.cidr)[1]) >= 8, false)
    ])
    error_message = "Supply 1-50 trusted IPv4 CIDRs, each /8 or narrower (prefer much narrower admin ranges)."
  }
}

variable "deletion_protection" {
  description = "Protection against accidental cluster deletion. Set false and apply before deliberately destroying."
  type        = bool
  default     = true
  nullable    = false
}

variable "maintenance_start_time" {
  description = "RFC3339 anchor for the recurring UTC maintenance window. Defaults to Saturday 00:00 UTC."
  type        = string
  default     = "2024-01-06T00:00:00Z"
}

variable "maintenance_end_time" {
  description = "RFC3339 end of the first window. Keep at least 48 hours of maintenance availability in each rolling 32 days."
  type        = string
  default     = "2024-01-08T00:00:00Z"
}

variable "maintenance_recurrence" {
  description = "RFC5545 recurrence for the maintenance window (default: 48 hours each weekend). GKE may perform emergency maintenance outside this window."
  type        = string
  default     = "FREQ=WEEKLY;BYDAY=SA"
}

variable "node_pools" {
  description = "On-demand regional pools. Autoscaling limits are TOTAL across zones, not per zone. At least three baseline nodes are required per pool. GKE distributes nodes across three zones in the region."
  type = map(object({
    machine_type      = optional(string, "e2-standard-4")
    disk_size_gb      = optional(number, 100)
    min_count         = optional(number, 3)
    max_count         = optional(number, 30)
    max_pods_per_node = optional(number, 32)
    labels            = optional(map(string), {})
    taints = optional(list(object({
      key    = string
      value  = string
      effect = string
    })), [])
  }))
  default  = { general = {} }
  nullable = false
  validation {
    condition = length(var.node_pools) > 0 && alltrue([
      for name, pool in var.node_pools :
      can(regex("^[a-z][a-z0-9-]{0,38}[a-z0-9]$", name)) &&
      pool.min_count >= 3 && pool.min_count == floor(pool.min_count) &&
      pool.max_count >= pool.min_count && pool.max_count == floor(pool.max_count) &&
      pool.disk_size_gb >= 100 && pool.disk_size_gb == floor(pool.disk_size_gb) &&
      contains([8, 16, 32, 64, 128, 256], pool.max_pods_per_node) &&
      alltrue([for taint in pool.taints : contains(["NO_SCHEDULE", "PREFER_NO_SCHEDULE", "NO_EXECUTE"], taint.effect)])
    ])
    error_message = "Use valid 2-40 character pool names, integer total min >= 3, max >= min, disk >= 100 GB, a supported max-pods power of two, and valid GKE taint effects."
  }
  validation {
    condition     = anytrue([for pool in values(var.node_pools) : alltrue([for taint in pool.taints : taint.effect == "PREFER_NO_SCHEDULE"])])
    error_message = "Keep at least one pool without hard taints so system workloads can be scheduled."
  }
}

variable "artifact_registry_repositories" {
  description = "Repositories that nodes may pull images from. Grant read access per repository, not across the project. Keys are stable identifiers."
  type = map(object({
    project_id    = string
    location      = string
    repository_id = string
  }))
  default  = {}
  nullable = false
}

variable "workload_identities" {
  description = "Optional Google service accounts and KSA impersonation bindings. Map keys are unique-in-project GSA account IDs; roles are explicitly chosen project-level workload grants. Prefer resource-level IAM managed by the owning service team where possible. Create/annotate the Kubernetes service accounts separately."
  type = map(object({
    namespace       = string
    service_account = string
    project_roles   = optional(set(string), [])
  }))
  default  = {}
  nullable = false
  validation {
    condition = alltrue([
      for account, workload in var.workload_identities :
      can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", account)) &&
      can(regex("^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$", workload.namespace)) &&
      can(regex("^[a-z0-9]([a-z0-9.-]{0,251}[a-z0-9])?$", workload.service_account)) &&
      alltrue([for role in workload.project_roles : !contains(["roles/owner", "roles/editor", "roles/viewer"], role)])
    ])
    error_message = "Use valid 6-30 character GSA IDs, Kubernetes namespace/service-account names and service-specific roles (not basic owner/editor/viewer)."
  }
}

variable "database_encryption_key" {
  description = "Optional full Cloud KMS CryptoKey resource name for application-layer Kubernetes Secret encryption. Key location must match the cluster region (or be global). Null uses GKE's default encryption at rest. Key and its API/lifecycle are owned externally."
  type        = string
  default     = null
}

variable "labels" {
  description = "Additional GCP cluster/node labels. environment and managed-by are reserved."
  type        = map(string)
  default     = {}
  nullable    = false
}
