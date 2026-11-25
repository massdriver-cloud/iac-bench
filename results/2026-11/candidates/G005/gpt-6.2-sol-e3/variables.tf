variable "project_id" {
  description = "ID of the Google Cloud project that owns the existing VPC and will host the cluster."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "project_id must be a Google Cloud project ID, not a project number or display name."
  }
}

variable "cluster_name" {
  description = "GKE cluster name, unique within the project and region."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-z]([a-z0-9-]{0,38}[a-z0-9])?$", var.cluster_name))
    error_message = "cluster_name must be 1–40 lowercase letters, digits, or hyphens, start with a letter, and end with a letter or digit."
  }
}

variable "region" {
  description = "US Google Cloud region containing the existing regional GKE subnet (for example, us-central1)."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^us-[a-z]+[0-9]+$", var.region))
    error_message = "region must be a US region such as us-central1, not a zone."
  }
}

variable "environment" {
  description = "Network environment. Selects the existing apps-staging or apps-prod VPC."
  type        = string
  nullable    = false

  validation {
    condition     = contains(["staging", "prod"], var.environment)
    error_message = "environment must be staging or prod."
  }
}

variable "node_pools" {
  description = "Regional on-demand Linux pools keyed by name. The autoscaling limits are per zone. Keep one untainted pool for shared cluster services."
  type = map(object({
    machine_type       = optional(string, "e2-standard-4")
    min_nodes_per_zone = optional(number, 1)
    max_nodes_per_zone = optional(number, 4)
    disk_size_gb       = optional(number, 100)
    labels             = optional(map(string), {})
    taints = optional(list(object({
      key    = string
      value  = string
      effect = string
    })), [])
  }))
  default  = { general = {} }
  nullable = false

  validation {
    condition = try(length(var.node_pools) > 0 && alltrue([
      for name, pool in var.node_pools :
      can(regex("^[a-z]([a-z0-9-]{0,38}[a-z0-9])?$", name)) && name != "default-pool" &&
      trimspace(pool.machine_type) != "" &&
      pool.min_nodes_per_zone >= 1 && floor(pool.min_nodes_per_zone) == pool.min_nodes_per_zone &&
      pool.max_nodes_per_zone >= pool.min_nodes_per_zone && floor(pool.max_nodes_per_zone) == pool.max_nodes_per_zone &&
      pool.disk_size_gb >= 30 && floor(pool.disk_size_gb) == pool.disk_size_gb &&
      alltrue([for taint in pool.taints : trimspace(taint.key) != "" && contains(["NO_SCHEDULE", "PREFER_NO_SCHEDULE", "NO_EXECUTE"], taint.effect)])
    ]), false)
    error_message = "Set at least one valid pool, not named default-pool, with a machine type, positive integer per-zone bounds (max >= min), a whole-number disk size of at least 30 GB, and valid GKE taints."
  }

  validation {
    condition     = try(anytrue([for pool in values(var.node_pools) : length(pool.taints) == 0]), false)
    error_message = "At least one node pool must be untainted."
  }
}

variable "maintenance_start_time" {
  description = "Start of the daily four-hour GKE maintenance window, in UTC (HH:MM)."
  type        = string
  default     = "05:00"
  nullable    = false

  validation {
    condition     = can(regex("^([01][0-9]|2[0-3]):[0-5][0-9]$", var.maintenance_start_time))
    error_message = "maintenance_start_time must be a valid 24-hour UTC time in HH:MM format."
  }
}

variable "deletion_protection" {
  description = "Prevent cluster deletion. For an intentional teardown, set false and apply before destroying."
  type        = bool
  default     = true
  nullable    = false
}
