variable "project_id" {
  description = "Project containing the cluster and the environment VPC."
  type        = string
  nullable    = false
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "Supply a Google Cloud project ID (not the project number)."
  }
}

variable "environment" {
  description = "Selects the network team's apps-staging or apps-prod VPC."
  type        = string
  nullable    = false
  validation {
    condition     = contains(["staging", "prod"], var.environment)
    error_message = "Use staging or prod."
  }
}

variable "region" {
  description = "US region with a provisioned GKE subnet and at least three supported zones."
  type        = string
  nullable    = false
  validation {
    condition     = can(regex("^us-[a-z]+[0-9]+$", var.region))
    error_message = "Specify a US region, not a zone."
  }
}

variable "cluster_name" {
  description = "Cluster name, unique within the project and region."
  type        = string
  nullable    = false
  validation {
    condition     = can(regex("^[a-z]([a-z0-9-]{0,38}[a-z0-9])?$", var.cluster_name))
    error_message = "Use a GKE cluster name of at most 40 lowercase letters, numbers and hyphens, starting with a letter and ending in a letter or number."
  }
}

variable "control_plane_cidr" {
  description = "Network-team allocated private, non-overlapping /28 for this control plane."
  type        = string
  nullable    = false
  validation {
    condition     = try(cidrnetmask(var.control_plane_cidr) == "255.255.255.240" && split("/", var.control_plane_cidr)[0] == cidrhost(var.control_plane_cidr, 0) && (startswith(var.control_plane_cidr, "10.") || startswith(var.control_plane_cidr, "192.168.") || can(regex("^172\\.(1[6-9]|2[0-9]|3[01])\\.", var.control_plane_cidr))), false)
    error_message = "Use a network-aligned RFC1918 IPv4 /28."
  }
}

variable "pool" {
  description = "General-purpose worker configuration. Bounds are per zone, not cluster totals."
  type = object({
    machine_type = optional(string, "e2-standard-4")
    min_per_zone = optional(number, 1)
    max_per_zone = optional(number, 5)
  })
  default  = {}
  nullable = false
  validation {
    condition     = var.pool.min_per_zone >= 1 && var.pool.max_per_zone >= var.pool.min_per_zone && floor(var.pool.min_per_zone) == var.pool.min_per_zone && floor(var.pool.max_per_zone) == var.pool.max_per_zone && trimspace(var.pool.machine_type) != ""
    error_message = "Supply a machine type and whole-number bounds with 1 <= min_per_zone <= max_per_zone."
  }
}
