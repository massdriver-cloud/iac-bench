variable "project_id" {
  description = "Google Cloud project that contains the cluster, VPC, and subnet."
  type        = string
}

variable "cluster_name" {
  description = "Name of the regional GKE Standard cluster."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,38}[a-z0-9]$", var.cluster_name))
    error_message = "cluster_name must be 2-40 characters, start with a lowercase letter, and contain only lowercase letters, digits, or hyphens (not ending in a hyphen)."
  }
}

variable "region" {
  description = "US region for the regional cluster and its GKE subnet."
  type        = string
}

variable "network_name" {
  description = "Existing VPC network name (for example, apps-staging or apps-prod)."
  type        = string
}

variable "master_ipv4_cidr_block" {
  description = "Unused /28 IPv4 range for the private GKE control-plane endpoint; choose a range that does not overlap your VPC or peered networks."
  type        = string

  validation {
    condition     = can(cidrnetmask(var.master_ipv4_cidr_block)) && tonumber(split("/", var.master_ipv4_cidr_block)[1]) == 28
    error_message = "master_ipv4_cidr_block must be a valid IPv4 /28 CIDR range."
  }
}

variable "authorized_master_networks" {
  description = "Optional client CIDRs allowed to reach the control plane. The private endpoint remains private; provide entries only if authorized-network enforcement is desired."
  type = list(object({
    cidr_block   = string
    display_name = optional(string)
  }))
  default = []

  validation {
    condition     = alltrue([for network in var.authorized_master_networks : can(cidrhost(network.cidr_block, 0))])
    error_message = "Each authorized master network must be a valid CIDR range."
  }
}

variable "release_channel" {
  description = "GKE release channel; REGULAR balances feature availability and stability."
  type        = string
  default     = "REGULAR"

  validation {
    condition     = contains(["RAPID", "REGULAR", "STABLE"], var.release_channel)
    error_message = "release_channel must be RAPID, REGULAR, or STABLE."
  }
}

variable "node_machine_type" {
  description = "Machine type used by the standard workload node pool."
  type        = string
  default     = "e2-standard-4"
}

variable "node_disk_size_gb" {
  description = "Boot disk size for each node, in GiB."
  type        = number
  default     = 100

  validation {
    condition     = var.node_disk_size_gb >= 20 && var.node_disk_size_gb <= 65536 && floor(var.node_disk_size_gb) == var.node_disk_size_gb
    error_message = "node_disk_size_gb must be a whole number between 20 and 65536."
  }
}

variable "node_min_count" {
  description = "Minimum autoscaled nodes per zone in the regional node pool."
  type        = number
  default     = 1

  validation {
    condition     = var.node_min_count >= 0 && floor(var.node_min_count) == var.node_min_count
    error_message = "node_min_count must be a whole number greater than or equal to zero."
  }
}

variable "node_max_count" {
  description = "Maximum autoscaled nodes per zone in the regional node pool."
  type        = number
  default     = 10

  validation {
    condition     = var.node_max_count >= 1 && floor(var.node_max_count) == var.node_max_count
    error_message = "node_max_count must be a whole number of at least 1."
  }
}

variable "environment" {
  description = "Environment label applied to cluster and node resources."
  type        = string
  default     = "production"

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9_-]{0,61}[a-z0-9])?$", lower(var.environment)))
    error_message = "environment must be a valid label value of at most 63 characters."
  }
}

variable "deletion_protection" {
  description = "Prevent accidental deletion of the production cluster."
  type        = bool
  default     = true
}
