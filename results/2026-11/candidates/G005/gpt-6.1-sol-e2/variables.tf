variable "project_id" {
  description = "Existing project containing both the cluster and environment VPC."
  type        = string
}

variable "cluster_name" {
  description = "Unique cluster name in the project/region."
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,38}[a-z0-9]$", var.cluster_name))
    error_message = "Use 2-40 lowercase letters, digits or hyphens, starting with a letter and ending with a letter or digit."
  }
}

variable "environment" {
  description = "Selects the existing apps-staging or apps-prod VPC."
  type        = string
  validation {
    condition     = contains(["staging", "prod"], var.environment)
    error_message = "Environment must be staging or prod."
  }
}

variable "region" {
  description = "US region containing the existing <vpc>-gke-<region> subnet."
  type        = string
  default     = "us-central1"
  validation {
    condition     = can(regex("^us-[a-z]+[0-9]+$", var.region))
    error_message = "Choose a US region, such as us-central1."
  }
}

variable "node_locations" {
  description = "Exactly three distinct zones in the region. Null selects the first three available zones."
  type        = list(string)
  default     = null
  validation {
    condition     = var.node_locations == null ? true : length(distinct(var.node_locations)) == 3
    error_message = "Specify exactly three distinct zones, or null."
  }
}

variable "control_plane_cidr" {
  description = "Unused, non-overlapping RFC1918 /28 for the private control plane; coordinate with the network team, especially across peered clusters."
  type        = string
  default     = "172.16.0.0/28"
  validation {
    condition = can(cidrnetmask(var.control_plane_cidr)) && can(regex("/28$", var.control_plane_cidr)) && (
      can(regex("^10\\.", var.control_plane_cidr)) ||
      can(regex("^172\\.(1[6-9]|2[0-9]|3[01])\\.", var.control_plane_cidr)) ||
      can(regex("^192\\.168\\.", var.control_plane_cidr))
    )
    error_message = "Supply a private IPv4 /28."
  }
}

variable "node_pools" {
  description = "Regional on-demand pools. Autoscaling limits are TOTAL across three zones, not per-zone. Size max_nodes for a zone failure and upgrades; use Kubernetes topology spread, PDBs and resource requests."
  type = map(object({
    machine_type = optional(string, "e2-standard-4")
    min_nodes    = optional(number, 3)
    max_nodes    = optional(number, 9)
    disk_size_gb = optional(number, 100)
    labels       = optional(map(string), {})
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
      pool.min_nodes >= 3 && pool.max_nodes >= pool.min_nodes &&
      floor(pool.min_nodes) == pool.min_nodes && floor(pool.max_nodes) == pool.max_nodes &&
      pool.disk_size_gb >= 100 && floor(pool.disk_size_gb) == pool.disk_size_gb &&
      alltrue([for taint in pool.taints : contains(["NO_SCHEDULE", "PREFER_NO_SCHEDULE", "NO_EXECUTE"], taint.effect)])
    ])
    error_message = "Provide at least one pool, valid 2-40 character names, integer limits max >= min >= 3, disks >= 100 GiB and valid taint effects."
  }
}

variable "deletion_protection" {
  description = "Protects the cluster against accidental deletion. Explicitly apply false before intentional teardown."
  type        = bool
  default     = true
}

variable "artifact_registry_projects" {
  description = "Projects whose Artifact Registry repositories nodes may read. Empty grants none; preferably grant repository-level reader access externally instead."
  type        = set(string)
  default     = []
}

variable "workload_identities" {
  description = "Optional dedicated Google service accounts keyed by a short identifier. Binds only the named Kubernetes service account; no application permissions are granted. Grant resource-scoped roles externally using the output emails."
  type = map(object({
    namespace                  = string
    kubernetes_service_account = string
  }))
  default = {}
  validation {
    condition = alltrue([for key, identity in var.workload_identities :
      can(regex("^[a-z][a-z0-9-]{0,18}[a-z0-9]$", key)) &&
      can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", identity.namespace)) &&
      can(regex("^[a-z0-9]([-a-z0-9.]*[a-z0-9])?$", identity.kubernetes_service_account))
    ])
    error_message = "Identity keys must be 2-20 lowercase characters; namespace and Kubernetes service account must be valid Kubernetes names."
  }
}
