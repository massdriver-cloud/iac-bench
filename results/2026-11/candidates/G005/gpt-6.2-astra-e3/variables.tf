variable "project_id" {
  description = "Google Cloud project ID containing the existing environment VPC."
  type        = string
  nullable    = false
}

variable "environment" {
  description = "Selects the network team's apps-staging or apps-prod VPC."
  type        = string
  nullable    = false
  validation {
    condition     = contains(["staging", "prod"], var.environment)
    error_message = "Choose staging or prod."
  }
}

variable "region" {
  description = "US region with an existing GKE subnet."
  type        = string
  nullable    = false
  validation {
    condition     = can(regex("^us-[a-z]+[0-9]+$", var.region))
    error_message = "Use a US region such as us-central1."
  }
}

variable "cluster_name" {
  description = "Name of this regional cluster."
  type        = string
  nullable    = false
  validation {
    condition     = can(regex("^[a-z]([a-z0-9-]{0,38}[a-z0-9])?$", var.cluster_name))
    error_message = "Use 1-40 lowercase letters, digits and hyphens, starting with a letter and ending with a letter or digit."
  }
}

variable "control_plane_cidr" {
  description = "Unused RFC1918 /28 allocated by the network team for this cluster's control plane."
  type        = string
  nullable    = false
  validation {
    condition     = try(split("/", var.control_plane_cidr)[1] == "28" && cidrhost(var.control_plane_cidr, 0) == split("/", var.control_plane_cidr)[0] && can(regex("^(10\\.|192\\.168\\.|172\\.(1[6-9]|2[0-9]|3[01])\\.)", var.control_plane_cidr)), false)
    error_message = "Supply a network-aligned private IPv4 /28."
  }
}

variable "worker_capacity" {
  description = "General-purpose worker sizing. Limits are per zone (normally three zones)."
  type = object({
    machine_type = string
    min_per_zone = number
    max_per_zone = number
  })
  default  = { machine_type = "e2-standard-4", min_per_zone = 1, max_per_zone = 5 }
  nullable = false
  validation {
    condition     = var.worker_capacity.min_per_zone >= 1 && floor(var.worker_capacity.min_per_zone) == var.worker_capacity.min_per_zone && var.worker_capacity.max_per_zone >= var.worker_capacity.min_per_zone && floor(var.worker_capacity.max_per_zone) == var.worker_capacity.max_per_zone
    error_message = "Use positive integer limits with max_per_zone >= min_per_zone."
  }
}

variable "deletion_protection" {
  description = "To decommission, explicitly set false and apply before destroying."
  type        = bool
  default     = true
  nullable    = false
}
