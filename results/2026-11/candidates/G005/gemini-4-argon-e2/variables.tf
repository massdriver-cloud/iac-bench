variable "project_id" {
  description = "The Google Cloud project ID where the GKE cluster and VPC reside."
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
    error_message = "cluster_name must start with a lowercase letter, contain only lowercase letters, numbers, and hyphens, and be at most 40 characters."
  }
}

variable "environment" {
  description = "The environment for this cluster ('staging' or 'prod'). Determines the VPC ('apps-staging' or 'apps-prod')."
  type        = string

  validation {
    condition     = contains(["staging", "prod"], var.environment)
    error_message = "environment must be either 'staging' or 'prod'."
  }
}

variable "region" {
  description = "The US Google Cloud region where the regional GKE cluster will be deployed (e.g., us-central1, us-east1)."
  type        = string

  validation {
    condition     = can(regex("^us-[a-z]+\\d+$", var.region))
    error_message = "region must be a valid US Google Cloud region (e.g., us-central1, us-east1, us-west1)."
  }
}

variable "master_ipv4_cidr_block" {
  description = "The /28 CIDR block for the GKE control plane private endpoint (must not overlap with VPC subnets)."
  type        = string
  default     = "172.16.0.0/28"

  validation {
    condition     = can(cidrhost(var.master_ipv4_cidr_block, 0)) && endswith(var.master_ipv4_cidr_block, "/28")
    error_message = "master_ipv4_cidr_block must be a valid IPv4 /28 CIDR block."
  }
}

variable "release_channel" {
  description = "The GKE release channel for automatic version upgrades (REGULAR, STABLE, or RAPID)."
  type        = string
  default     = "REGULAR"

  validation {
    condition     = contains(["REGULAR", "STABLE", "RAPID"], var.release_channel)
    error_message = "release_channel must be one of REGULAR, STABLE, or RAPID."
  }
}

variable "enable_private_endpoint" {
  description = "Whether the control plane's public endpoint is disabled (true = private endpoint only, false = public endpoint enabled with master_authorized_networks)."
  type        = bool
  default     = false
}

variable "master_authorized_networks" {
  description = "List of CIDR blocks permitted to reach the GKE control plane endpoint."
  type = list(object({
    cidr_block   = string
    display_name = string
  }))
  default = []

  validation {
    condition     = alltrue([for net in var.master_authorized_networks : can(cidrhost(net.cidr_block, 0))])
    error_message = "Every entry in master_authorized_networks must have a valid IPv4 CIDR block."
  }
}

variable "deletion_protection" {
  description = "Whether Terraform/OpenTofu deletion protection is enabled on the GKE cluster."
  type        = bool
  default     = true
}

variable "maintenance_start_time" {
  description = "Daily maintenance window start time in GMT (HH:MM format)."
  type        = string
  default     = "03:00"

  validation {
    condition     = can(regex("^([01]\\d|2[0-3]):[0-5]\\d$", var.maintenance_start_time))
    error_message = "maintenance_start_time must be in HH:MM 24-hour format (e.g., 03:00)."
  }
}

variable "node_pools" {
  description = "Map of GKE Standard node pool configurations. Key is the node pool name."
  type = map(object({
    machine_type       = optional(string, "e2-standard-4")
    disk_size_gb       = optional(number, 100)
    disk_type          = optional(string, "pd-balanced")
    min_node_count     = optional(number, 1)
    max_node_count     = optional(number, 5)
    initial_node_count = optional(number, 1)
    spot               = optional(bool, false)
    max_surge          = optional(number, 1)
    max_unavailable    = optional(number, 0)
    labels             = optional(map(string), {})
    tags               = optional(list(string), [])
    taints = optional(list(object({
      key    = string
      value  = string
      effect = string
    })), [])
  }))

  default = {
    general = {
      machine_type       = "e2-standard-4"
      disk_size_gb       = 100
      disk_type          = "pd-balanced"
      min_node_count     = 1
      max_node_count     = 5
      initial_node_count = 1
    }
  }

  validation {
    condition     = length(var.node_pools) > 0
    error_message = "At least one node pool must be defined in node_pools."
  }
}

variable "labels" {
  description = "Additional resource labels to apply to the GKE cluster and nodes."
  type        = map(string)
  default     = {}
}
