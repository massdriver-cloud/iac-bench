variable "project_id" {
  description = "Existing project containing the cluster and the environment VPC."
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "Supply a valid Google Cloud project ID."
  }
}

variable "name" {
  description = "Cluster name; also used to name dedicated service accounts. Use a unique name in this project."
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,18}[a-z0-9]$", var.name))
    error_message = "Name must be 2-20 lowercase letters, digits or hyphens, starting with a letter and ending alphanumeric."
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
  description = "US region containing the existing <vpc>-gke-<region> subnet. Regional control planes span zones."
  type        = string
  validation {
    condition     = can(regex("^us-[a-z]+[0-9]+$", var.region))
    error_message = "Use a US region, for example us-central1."
  }
}

variable "control_plane_ipv4_cidr" {
  description = "Unique RFC1918 /28 for the control plane. Must not overlap any subnet, secondary range, peered network or other cluster control plane."
  type        = string
  validation {
    condition = can(cidrhost(var.control_plane_ipv4_cidr, 0)) && can(regex("/28$", var.control_plane_ipv4_cidr)) && (
      can(regex("^10\\.", var.control_plane_ipv4_cidr)) ||
      can(regex("^192\\.168\\.", var.control_plane_ipv4_cidr)) ||
      can(regex("^172\\.(1[6-9]|2[0-9]|3[01])\\.", var.control_plane_ipv4_cidr))
    )
    error_message = "Provide a non-overlapping RFC1918 IPv4 /28."
  }
}

variable "authorized_networks" {
  description = "Private operator/CI source CIDRs permitted to access the private Kubernetes API. Empty denies external clients; cluster-required access is retained by GKE."
  type        = map(string)
  default     = {}
  validation {
    condition     = alltrue([for cidr in values(var.authorized_networks) : can(cidrnetmask(cidr)) && !endswith(cidr, "/0")])
    error_message = "Authorized networks must be IPv4 CIDRs, not a default route."
  }
}

variable "node_locations" {
  description = "Optional explicit zones in the selected region; at least three distinct zones. Null lets GKE choose three zones."
  type        = list(string)
  default     = null
  validation {
    condition     = var.node_locations == null ? true : length(distinct(var.node_locations)) >= 3
    error_message = "Choose at least three distinct zones for production resilience."
  }
}

variable "node_pools" {
  description = "On-demand pools. Autoscaling bounds are PER ZONE (default 3-9 nodes across three zones). No spot nodes. All pools retain capacity in each zone."
  type = map(object({
    machine_type   = optional(string, "e2-standard-4")
    disk_size_gb   = optional(number, 100)
    min_node_count = optional(number, 1)
    max_node_count = optional(number, 3)
    max_pods       = optional(number, 64)
    labels         = optional(map(string), {})
  }))
  default = { general = {} }
  validation {
    condition = length(var.node_pools) > 0 && alltrue([for name, pool in var.node_pools :
      can(regex("^[a-z][a-z0-9-]{0,38}[a-z0-9]$", name)) &&
      pool.min_node_count >= 1 && floor(pool.min_node_count) == pool.min_node_count &&
      pool.max_node_count >= pool.min_node_count && floor(pool.max_node_count) == pool.max_node_count &&
      pool.disk_size_gb >= 100 && floor(pool.disk_size_gb) == pool.disk_size_gb &&
      contains([8, 16, 32, 64, 110, 128, 256], pool.max_pods)
    ])
    error_message = "Provide at least one valid named pool, integer min >= 1 and max >= min per zone, disks >= 100GB and a supported max_pods value."
  }
}

variable "deletion_protection" {
  description = "Protect the cluster from accidental destroy; explicitly set false and apply before destroying."
  type        = bool
  default     = true
}

variable "maintenance_start_time" {
  description = "RFC3339 start of recurring daily four-hour maintenance window (UTC). Daily recurrence meets GKE maintenance availability requirements."
  type        = string
  default     = "2025-01-01T06:00:00Z"
  validation {
    condition     = can(timeadd(var.maintenance_start_time, "4h"))
    error_message = "Use an RFC3339 timestamp."
  }
}

variable "security_group" {
  description = "Optional gke-security-groups@your-domain group for Google Groups Kubernetes RBAC. RBAC grants remain the platform team's responsibility."
  type        = string
  default     = null
}

variable "artifact_registry_repositories" {
  description = "Repositories nodes may pull images from, keyed by a stable alias. Grants reader at repository scope only."
  type = map(object({
    project    = string
    location   = string
    repository = string
  }))
  default = {}
}

variable "workload_identities" {
  description = "Optional dedicated Google service accounts, keyed by short ID. Each trusts exactly one Kubernetes namespace/service-account pair. Project roles are explicit opt-in; prefer resource-level grants outside this module where practical."
  type = map(object({
    namespace       = string
    service_account = string
    project_roles   = optional(set(string), [])
  }))
  default = {}
  validation {
    condition = alltrue([for key, identity in var.workload_identities :
      can(regex("^[a-z][a-z0-9-]{0,6}[a-z0-9]$", key)) &&
      can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", identity.namespace)) && length(identity.namespace) <= 63 &&
      can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", identity.service_account)) && length(identity.service_account) <= 63 &&
      alltrue([for role in identity.project_roles : !contains(["roles/owner", "roles/editor", "roles/viewer"], role)])
    ])
    error_message = "Identity keys must be 2-8 lowercase alphanumeric/hyphen characters, starting with a letter; use valid Kubernetes names and no primitive project roles."
  }
}
