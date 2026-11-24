variable "project_id" {
  description = "ID of the project containing the environment VPC."
  type        = string
  nullable    = false
}

variable "environment" {
  description = "Environment; selects the apps-<environment> VPC."
  type        = string
  nullable    = false
  validation {
    condition     = contains(["staging", "prod"], var.environment)
    error_message = "Environment must be staging or prod."
  }
}

variable "region" {
  description = "US region containing the existing GKE subnet (not a zone)."
  type        = string
  nullable    = false
  validation {
    condition     = can(regex("^us-[a-z]+[0-9]+$", var.region))
    error_message = "Supply a US region such as us-central1."
  }
}

variable "cluster_name" {
  description = "GKE cluster name."
  type        = string
  nullable    = false
  validation {
    condition     = can(regex("^[a-z]([a-z0-9-]{0,38}[a-z0-9])?$", var.cluster_name))
    error_message = "Use at most 40 lowercase letters, numbers or hyphens, beginning with a letter and ending with a letter or number."
  }
}

variable "control_plane_cidr" {
  description = "Network-team allocated non-overlapping private IPv4 /28 for this control plane."
  type        = string
  nullable    = false
  validation {
    condition     = try(cidrnetmask(var.control_plane_cidr) == "255.255.255.240" && cidrhost(var.control_plane_cidr, 0) == split("/", var.control_plane_cidr)[0], false)
    error_message = "Supply a network-aligned IPv4 /28."
  }
}

variable "node_machine_type" {
  description = "General-purpose worker VM machine type."
  type        = string
  default     = "e2-standard-4"
}

variable "max_nodes_per_zone" {
  description = "Autoscaling ceiling per zone; minimum is one node per zone."
  type        = number
  default     = 5
  validation {
    condition     = var.max_nodes_per_zone >= 1 && floor(var.max_nodes_per_zone) == var.max_nodes_per_zone
    error_message = "Use a positive integer."
  }
}

variable "deletion_protection" {
  description = "Set false and apply before intentionally destroying a cluster."
  type        = bool
  default     = true
}
