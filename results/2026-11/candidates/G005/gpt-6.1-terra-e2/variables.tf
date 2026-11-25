variable "project_id" {
  description = "Project containing the cluster and the existing VPC."
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "project_id must be a valid Google Cloud project ID."
  }
}

variable "environment" {
  description = "Environment whose network is used: staging or prod."
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
  description = "Name of the regional GKE cluster."
  type        = string
  validation {
    condition     = length(var.cluster_name) <= 40 && can(regex("^[a-z]([-a-z0-9]*[a-z0-9])?$", var.cluster_name))
    error_message = "cluster_name must be 1-40 lowercase letters, digits and hyphens, starting with a letter and ending with a letter or digit."
  }
}

variable "master_ipv4_cidr_block" {
  description = "An unused, non-overlapping RFC 1918 /28 for the GKE control plane; coordinate with the network team."
  type        = string
  validation {
    condition = try(
      cidrnetmask(var.master_ipv4_cidr_block) == "255.255.255.240" &&
      cidrhost(var.master_ipv4_cidr_block, 0) == split("/", var.master_ipv4_cidr_block)[0] &&
      (cidrcontains("10.0.0.0/8", cidrhost(var.master_ipv4_cidr_block, 0)) ||
        cidrcontains("172.16.0.0/12", cidrhost(var.master_ipv4_cidr_block, 0)) ||
    cidrcontains("192.168.0.0/16", cidrhost(var.master_ipv4_cidr_block, 0))), false)
    error_message = "master_ipv4_cidr_block must be a canonical RFC 1918 /28."
  }
}

variable "master_authorized_networks" {
  description = "Trusted IPv4 CIDRs allowed to access the control-plane public endpoint. Never use 0.0.0.0/0."
  type = list(object({
    display_name = string
    cidr_block   = string
  }))
  validation {
    condition = length(var.master_authorized_networks) > 0 && alltrue([
      for n in var.master_authorized_networks : try(
        length(trimspace(n.display_name)) > 0 && cidrnetmask(n.cidr_block) != "0.0.0.0" &&
      cidrhost(n.cidr_block, 0) == split("/", n.cidr_block)[0], false)
    ])
    error_message = "Provide at least one named canonical IPv4 CIDR other than 0.0.0.0/0."
  }
}

variable "private_endpoint" {
  description = "Use only the private control-plane endpoint. Requires operator connectivity to the control-plane network."
  type        = bool
  default     = false
}

variable "machine_type" {
  description = "Machine type for the general-purpose node pool."
  type        = string
  default     = "e2-standard-4"
}

variable "node_disk_size_gb" {
  description = "Boot disk size for each node."
  type        = number
  default     = 100
  validation {
    condition     = var.node_disk_size_gb >= 100 && floor(var.node_disk_size_gb) == var.node_disk_size_gb
    error_message = "node_disk_size_gb must be an integer of at least 100."
  }
}

variable "min_nodes_per_zone" {
  description = "Minimum nodes per zone in the regional pool."
  type        = number
  default     = 1
  validation {
    condition     = var.min_nodes_per_zone >= 1 && floor(var.min_nodes_per_zone) == var.min_nodes_per_zone
    error_message = "min_nodes_per_zone must be an integer of at least 1."
  }
}

variable "max_nodes_per_zone" {
  description = "Maximum nodes per zone in the regional pool."
  type        = number
  default     = 3
  validation {
    condition     = var.max_nodes_per_zone >= 1 && floor(var.max_nodes_per_zone) == var.max_nodes_per_zone
    error_message = "max_nodes_per_zone must be an integer of at least 1."
  }
}

variable "maintenance_start_time" {
  description = "Start of the daily four-hour GKE maintenance window in UTC (HH:MM)."
  type        = string
  default     = "09:00"
  validation {
    condition     = can(regex("^([01][0-9]|2[0-3]):[0-5][0-9]$", var.maintenance_start_time))
    error_message = "maintenance_start_time must use 24-hour HH:MM UTC."
  }
}

variable "deletion_protection" {
  description = "Prevent cluster deletion through OpenTofu. Set false and apply before intentional destruction."
  type        = bool
  default     = true
}
