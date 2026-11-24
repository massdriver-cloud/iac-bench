variable "project_id" {
  description = "Project containing both the cluster and the environment VPC."
  type        = string
}

variable "environment" {
  description = "Environment whose existing VPC and subnet the cluster uses."
  type        = string
  validation {
    condition     = contains(["staging", "prod"], var.environment)
    error_message = "environment must be staging or prod."
  }
}

variable "region" {
  description = "US region containing the existing GKE subnet."
  type        = string
  validation {
    condition     = can(regex("^us-[a-z]+[0-9]+$", var.region))
    error_message = "region must be a US region, such as us-central1."
  }
}

variable "cluster_name" {
  description = "GKE cluster name, unique within the project and region."
  type        = string
  validation {
    condition     = can(regex("^[a-z]([-a-z0-9]*[a-z0-9])?$", var.cluster_name)) && length(var.cluster_name) <= 40
    error_message = "cluster_name must be 1-40 lowercase letters, digits or hyphens, starting with a letter and ending with a letter or digit."
  }
}

variable "master_ipv4_cidr_block" {
  description = "A unique, unused RFC1918 /28 for the GKE control plane; must not overlap VPC, peered, or on-prem ranges."
  type        = string
  validation {
    condition = can(cidrnetmask(var.master_ipv4_cidr_block)) && try(tonumber(split("/", var.master_ipv4_cidr_block)[1]) == 28, false) && (
      try(cidrcontains("10.0.0.0/8", cidrhost(var.master_ipv4_cidr_block, 0)), false) ||
      try(cidrcontains("172.16.0.0/12", cidrhost(var.master_ipv4_cidr_block, 0)), false) ||
      try(cidrcontains("192.168.0.0/16", cidrhost(var.master_ipv4_cidr_block, 0)), false)
    )
    error_message = "master_ipv4_cidr_block must be an RFC1918 IPv4 /28."
  }
}

variable "control_plane_authorized_cidrs" {
  description = "Trusted administrator IPv4 CIDRs permitted to reach the public Kubernetes API endpoint. Never use 0.0.0.0/0."
  type        = map(string)
  validation {
    condition = length(var.control_plane_authorized_cidrs) > 0 && alltrue([
      for name, cidr in var.control_plane_authorized_cidrs : length(name) > 0 && can(cidrnetmask(cidr)) && try(tonumber(split("/", cidr)[1]) > 0, false)
    ])
    error_message = "Provide at least one named, valid IPv4 CIDR, excluding 0.0.0.0/0."
  }
}

variable "node_machine_type" {
  description = "Machine type for the standard node pool."
  type        = string
  default     = "e2-standard-4"
}

variable "max_nodes_per_zone" {
  description = "Autoscaling ceiling in each node zone; at least one node per zone is maintained."
  type        = number
  default     = 3
  validation {
    condition     = var.max_nodes_per_zone >= 1 && floor(var.max_nodes_per_zone) == var.max_nodes_per_zone
    error_message = "max_nodes_per_zone must be a positive integer."
  }
}

variable "deletion_protection" {
  description = "Protect the cluster from Terraform/OpenTofu deletion. Set false and apply before intentionally destroying it."
  type        = bool
  default     = true
}
