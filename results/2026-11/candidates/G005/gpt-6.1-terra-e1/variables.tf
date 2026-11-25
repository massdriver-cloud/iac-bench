variable "project_id" {
  description = "Project containing the cluster and environment VPC."
  type        = string
}

variable "cluster_name" {
  description = "Cluster name; also used to name its dedicated node service account."
  type        = string
  validation {
    condition     = length(var.cluster_name) >= 2 && length(var.cluster_name) <= 26 && can(regex("^[a-z]([-a-z0-9]*[a-z0-9])?$", var.cluster_name))
    error_message = "Use 2-26 lowercase letters, digits or hyphens, starting with a letter and ending with a letter or digit."
  }
}

variable "environment" {
  description = "Environment owning the apps-<environment> VPC."
  type        = string
  validation {
    condition     = contains(["staging", "prod"], var.environment)
    error_message = "Environment must be staging or prod."
  }
}

variable "region" {
  description = "US region containing the pre-existing GKE subnet."
  type        = string
  validation {
    condition     = can(regex("^us-[a-z]+[0-9]+$", var.region))
    error_message = "Region must be a US region, for example us-central1."
  }
}

variable "zones" {
  description = "Three distinct available zones in the region, for regional control plane and node pool placement."
  type        = set(string)
  validation {
    condition     = length(var.zones) == 3 && alltrue([for zone in var.zones : startswith(zone, "${var.region}-") && can(regex("-[a-z]$", zone))])
    error_message = "Specify three distinct zones in the selected region."
  }
}

variable "master_ipv4_cidr_block" {
  description = "A dedicated, non-overlapping RFC1918 /28 for the private GKE control plane."
  type        = string
  validation {
    condition = can(cidrnetmask(var.master_ipv4_cidr_block)) && try(
      endswith(var.master_ipv4_cidr_block, "/28") && cidrhost(var.master_ipv4_cidr_block, 0) == split("/", var.master_ipv4_cidr_block)[0] && (
        cidrcontains("10.0.0.0/8", cidrhost(var.master_ipv4_cidr_block, 0)) ||
        cidrcontains("172.16.0.0/12", cidrhost(var.master_ipv4_cidr_block, 0)) ||
        cidrcontains("192.168.0.0/16", cidrhost(var.master_ipv4_cidr_block, 0))
    ), false)
    error_message = "Provide a canonical RFC1918 IPv4 /28 that does not overlap any connected network."
  }
}

variable "admin_cidrs" {
  description = "IPv4 CIDRs of trusted private operator networks allowed to reach the private Kubernetes API. Connectivity and routes must exist separately."
  type        = set(string)
  validation {
    condition     = length(var.admin_cidrs) > 0 && length(var.admin_cidrs) <= 50 && alltrue([for cidr in var.admin_cidrs : can(cidrnetmask(cidr)) && cidr != "0.0.0.0/0"])
    error_message = "Supply 1-50 IPv4 CIDRs, excluding 0.0.0.0/0."
  }
}

variable "node_machine_type" {
  description = "Machine type for the general-purpose node pool."
  type        = string
  default     = "e2-standard-4"
}

variable "min_nodes_per_zone" {
  description = "Minimum node count in each zone."
  type        = number
  default     = 1
  validation {
    condition     = var.min_nodes_per_zone >= 1 && floor(var.min_nodes_per_zone) == var.min_nodes_per_zone
    error_message = "At least one whole node per zone is required."
  }
}

variable "max_nodes_per_zone" {
  description = "Maximum autoscaled node count in each zone."
  type        = number
  default     = 4
  validation {
    condition     = var.max_nodes_per_zone >= var.min_nodes_per_zone && floor(var.max_nodes_per_zone) == var.max_nodes_per_zone
    error_message = "Maximum must be a whole number at least as large as the minimum."
  }
}

variable "deletion_protection" {
  description = "Protect the cluster from accidental OpenTofu deletion. Set false and apply before intentional destruction."
  type        = bool
  default     = true
}
