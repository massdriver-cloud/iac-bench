variable "project_id" {
  description = "Google Cloud project ID for both the cluster and the existing VPC/subnet."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "project_id must be a Google Cloud project ID, not a project number or display name."
  }
}

variable "cluster_name" {
  description = "Name of the regional GKE cluster."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-z]([a-z0-9-]{0,38}[a-z0-9])?$", var.cluster_name))
    error_message = "cluster_name must be 1–40 characters, start with a lowercase letter, contain only lowercase letters, digits, and hyphens, and not end in a hyphen."
  }
}

variable "environment" {
  description = "Environment that selects the existing apps-staging or apps-prod VPC."
  type        = string
  nullable    = false

  validation {
    condition     = contains(["staging", "prod"], var.environment)
    error_message = "environment must be staging or prod."
  }
}

variable "region" {
  description = "US region containing the existing GKE subnet, such as us-central1."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^us-[a-z]+[0-9]+$", var.region))
    error_message = "region must be a US Google Cloud region (for example, us-central1)."
  }
}

variable "node_locations" {
  description = "Optional three distinct zones in the selected region. Null lets GKE choose the regional cluster's default zones."
  type        = set(string)
  default     = null

  validation {
    condition = var.node_locations == null ? true : (
      length(var.node_locations) == 3 && alltrue([
        for zone in var.node_locations : can(regex("^us-[a-z]+[0-9]+-[a-z]$", zone))
      ])
    )
    error_message = "When set, node_locations must contain three distinct US zone names."
  }
}

variable "node_pools" {
  description = "Managed node pools keyed by GKE pool name. Bounds apply per zone. Supplying this map replaces the default general pool."
  type = map(object({
    machine_type       = optional(string, "e2-standard-4")
    min_nodes_per_zone = optional(number, 1)
    max_nodes_per_zone = optional(number, 3)
    disk_size_gb       = optional(number, 100)
  }))
  nullable = false
  default  = { general = {} }

  validation {
    condition = length(var.node_pools) > 0 && alltrue([
      for name, pool in var.node_pools : try(
        can(regex("^[a-z]([a-z0-9-]{0,38}[a-z0-9])?$", name)) && name != "default-pool" &&
        length(trimspace(pool.machine_type)) > 0 &&
        pool.min_nodes_per_zone >= 1 && floor(pool.min_nodes_per_zone) == pool.min_nodes_per_zone &&
        pool.max_nodes_per_zone >= pool.min_nodes_per_zone && floor(pool.max_nodes_per_zone) == pool.max_nodes_per_zone &&
        pool.disk_size_gb >= 20 && pool.disk_size_gb <= 65536 && floor(pool.disk_size_gb) == pool.disk_size_gb,
        false
      )
    ])
    error_message = "Supply at least one pool. Use valid GKE pool names other than default-pool, nonempty machine types, integer per-zone bounds with 1 <= min <= max, and integer disk sizes from 20 to 65536 GiB."
  }
}

variable "maintenance_start_time" {
  description = "Start of the daily GKE maintenance window, in UTC (HH:MM)."
  type        = string
  default     = "08:00"
  nullable    = false

  validation {
    condition     = can(regex("^([01][0-9]|2[0-3]):[0-5][0-9]$", var.maintenance_start_time))
    error_message = "maintenance_start_time must use 24-hour HH:MM UTC format."
  }
}

variable "deletion_protection" {
  description = "Prevent cluster deletion. To decommission a cluster, set false and apply the change before destroying it."
  type        = bool
  default     = true
  nullable    = false
}

variable "resource_labels" {
  description = "Extra GKE cluster and node pool resource labels. The module owns the environment label."
  type        = map(string)
  default     = {}
  nullable    = false
}
