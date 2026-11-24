variable "project_id" {
  description = "Google Cloud project that owns the cluster and the selected VPC."
  type        = string
}

variable "cluster_name" {
  description = "Name of the GKE Standard cluster."
  type        = string

  validation {
    condition     = length(var.cluster_name) <= 40 && can(regex("^[a-z]([-a-z0-9]*[a-z0-9])?$", var.cluster_name))
    error_message = "cluster_name must be a valid GKE name: lowercase letters, digits, and hyphens; 1-40 characters; start with a letter and end alphanumeric."
  }
}

variable "region" {
  description = "US region for the regional GKE cluster."
  type        = string
}

variable "vpc_name" {
  description = "Existing environment VPC name (for example, apps-staging or apps-prod)."
  type        = string
}

variable "master_ipv4_cidr_block" {
  description = "Unused, non-overlapping /28 range for the private GKE control plane."
  type        = string

  validation {
    condition     = can(cidrhost(var.master_ipv4_cidr_block, 0)) && can(regex("/28$", var.master_ipv4_cidr_block))
    error_message = "master_ipv4_cidr_block must be a valid IPv4 /28 CIDR range."
  }
}

variable "authorized_master_networks" {
  description = "Trusted client CIDRs allowed to reach the public Kubernetes control-plane endpoint. Never use 0.0.0.0/0."
  type = list(object({
    cidr_block   = string
    display_name = string
  }))

  validation {
    condition = length(var.authorized_master_networks) > 0 && alltrue([
      for network in var.authorized_master_networks : network.cidr_block != "0.0.0.0/0" && network.cidr_block != "::/0"
    ])
    error_message = "Supply at least one trusted control-plane CIDR and do not allow all IPv4 or IPv6 addresses."
  }
}

variable "machine_type" {
  description = "Machine type for the managed worker pool."
  type        = string
  default     = "e2-standard-4"
}

variable "min_nodes_per_zone" {
  description = "Autoscaler minimum worker count in each cluster zone. Regional clusters use three zones by default."
  type        = number
  default     = 1

  validation {
    condition     = var.min_nodes_per_zone >= 1 && floor(var.min_nodes_per_zone) == var.min_nodes_per_zone
    error_message = "min_nodes_per_zone must be a positive whole number."
  }
}

variable "max_nodes_per_zone" {
  description = "Autoscaler maximum worker count in each cluster zone."
  type        = number
  default     = 10

  validation {
    condition     = var.max_nodes_per_zone >= 1 && floor(var.max_nodes_per_zone) == var.max_nodes_per_zone
    error_message = "max_nodes_per_zone must be a positive whole number."
  }
}

variable "maintenance_start_time" {
  description = "Daily UTC start time for the GKE maintenance window, in HH:MM format."
  type        = string
  default     = "03:00"

  validation {
    condition     = can(regex("^([01][0-9]|2[0-3]):[0-5][0-9]$", var.maintenance_start_time))
    error_message = "maintenance_start_time must be a 24-hour HH:MM time in UTC."
  }
}
