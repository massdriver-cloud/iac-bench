variable "project_id" {
  description = "The Google Cloud project ID where the GKE cluster and existing VPC reside."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "project_id must be a valid Google Cloud project ID (6-30 characters, lowercase letters, digits, and hyphens)."
  }
}

variable "cluster_name" {
  description = "The name of the GKE cluster."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,38}[a-z0-9]$", var.cluster_name))
    error_message = "cluster_name must be 2-40 characters, start with a lowercase letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "environment" {
  description = "Target environment, determining the shared VPC network (e.g., 'staging' maps to 'apps-staging', 'prod' maps to 'apps-prod')."
  type        = string

  validation {
    condition     = contains(["staging", "prod"], var.environment)
    error_message = "environment must be either 'staging' or 'prod'."
  }
}

variable "region" {
  description = "The US Google Cloud region in which to create the regional GKE cluster (e.g., us-central1, us-east1, us-west1)."
  type        = string

  validation {
    condition     = can(regex("^us-[a-z]+\\d+$", var.region))
    error_message = "region must be a valid US Google Cloud region (e.g., us-central1, us-east1)."
  }
}

variable "master_ipv4_cidr_block" {
  description = "The /28 IPv4 CIDR block for the private GKE control plane. Must not overlap with VPC subnets or other clusters."
  type        = string
  default     = "172.16.0.0/28"

  validation {
    condition     = can(cidrhost(var.master_ipv4_cidr_block, 0)) && endswith(var.master_ipv4_cidr_block, "/28")
    error_message = "master_ipv4_cidr_block must be a valid IPv4 CIDR block with a /28 prefix length."
  }
}

variable "master_authorized_networks" {
  description = "List of CIDR blocks permitted to reach the GKE control plane endpoint."
  type = list(object({
    cidr_block   = string
    display_name = string
  }))
  default = []

  validation {
    condition     = alltrue([for n in var.master_authorized_networks : can(cidrhost(n.cidr_block, 0))])
    error_message = "Each entry in master_authorized_networks must have a valid IPv4 cidr_block."
  }
}

variable "enable_private_endpoint" {
  description = "Whether the control plane's public endpoint is disabled, restricting access strictly to internal VPC / VPN / Interconnect networks."
  type        = bool
  default     = false
}

variable "release_channel" {
  description = "The GKE release channel for automated version upgrades and security patching."
  type        = string
  default     = "REGULAR"

  validation {
    condition     = contains(["RAPID", "REGULAR", "STABLE"], var.release_channel)
    error_message = "release_channel must be one of RAPID, REGULAR, or STABLE."
  }
}

variable "maintenance_start_time" {
  description = "Daily maintenance window start time in RFC3339 or HH:MM (UTC) format."
  type        = string
  default     = "03:00"
}

variable "deletion_protection" {
  description = "Whether to enable Terraform/GKE deletion protection on the cluster."
  type        = bool
  default     = true
}

variable "node_pools" {
  description = "Map of managed GKE Standard node pool configurations."
  type = map(object({
    machine_type    = optional(string, "e2-standard-4")
    min_node_count  = optional(number, 1)
    max_node_count  = optional(number, 5)
    disk_size_gb    = optional(number, 100)
    disk_type       = optional(string, "pd-balanced")
    image_type      = optional(string, "COS_CONTAINERD")
    spot            = optional(bool, false)
    max_surge       = optional(number, 1)
    max_unavailable = optional(number, 0)
    node_locations  = optional(list(string), null)
    labels          = optional(map(string), {})
    tags            = optional(list(string), [])
    taints = optional(list(object({
      key    = string
      value  = string
      effect = string
    })), [])
  }))
  default = {
    default = {
      machine_type   = "e2-standard-4"
      min_node_count = 1
      max_node_count = 5
      disk_size_gb   = 100
      disk_type      = "pd-balanced"
    }
  }

  validation {
    condition     = length(var.node_pools) > 0
    error_message = "At least one node pool must be defined in node_pools."
  }

  validation {
    condition = alltrue([
      for k, np in var.node_pools : np.min_node_count >= 0 && np.max_node_count >= np.min_node_count && np.max_node_count > 0
    ])
    error_message = "Each node pool must have min_node_count >= 0, max_node_count >= min_node_count, and max_node_count > 0."
  }
}

variable "labels" {
  description = "Additional resource labels to apply to the cluster and nodes."
  type        = map(string)
  default     = {}
}
