variable "project_id" {
  description = "The Google Cloud project ID where the GKE cluster and VPC reside."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "project_id must be a valid Google Cloud project ID (6-30 lowercase letters, digits, or hyphens)."
  }
}

variable "cluster_name" {
  description = "The name of the GKE Standard cluster."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,38}[a-z0-9]$", var.cluster_name))
    error_message = "cluster_name must be 2-40 characters, start with a lowercase letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "environment" {
  description = "The target deployment environment ('staging' or 'prod'). Maps to the network team's VPC ('apps-staging' or 'apps-prod')."
  type        = string

  validation {
    condition     = contains(["staging", "prod"], var.environment)
    error_message = "environment must be either 'staging' or 'prod' (corresponding to VPCs 'apps-staging' and 'apps-prod')."
  }
}

variable "region" {
  description = "The Google Cloud US region for the regional GKE cluster (e.g., us-central1, us-east1, us-west1)."
  type        = string

  validation {
    condition     = can(regex("^us-[a-z]+[0-9]$", var.region))
    error_message = "region must be a valid Google Cloud US region (e.g., us-central1, us-east1, us-east4, us-west1)."
  }
}

variable "master_ipv4_cidr_block" {
  description = "The /28 CIDR block for the GKE private control plane. Must not overlap with VPC subnets or other clusters."
  type        = string
  default     = "172.16.0.0/28"

  validation {
    condition     = can(cidrnetmask(var.master_ipv4_cidr_block)) && endswith(var.master_ipv4_cidr_block, "/28")
    error_message = "master_ipv4_cidr_block must be a valid IPv4 CIDR block with a /28 prefix length."
  }
}

variable "master_authorized_networks" {
  description = "Optional list of CIDR blocks permitted to reach the Kubernetes API server endpoint."
  type = list(object({
    cidr_block   = string
    display_name = string
  }))
  default = []
}

variable "enable_private_endpoint" {
  description = "Whether the Kubernetes API server is accessible only via the private IP address."
  type        = bool
  default     = false
}

variable "release_channel" {
  description = "The GKE release channel for automated version upgrades ('REGULAR' or 'STABLE')."
  type        = string
  default     = "REGULAR"

  validation {
    condition     = contains(["REGULAR", "STABLE", "RAPID"], var.release_channel)
    error_message = "release_channel must be one of 'REGULAR', 'STABLE', or 'RAPID'."
  }
}

variable "deletion_protection" {
  description = "Whether deletion protection is enabled on the GKE cluster."
  type        = bool
  default     = true
}

variable "kms_key_self_link" {
  description = "Optional Cloud KMS crypto key self_link to enable application-layer secrets encryption in etcd."
  type        = string
  default     = null
}

variable "notification_pubsub_topic" {
  description = "Optional Pub/Sub topic ID (projects/<project>/topics/<topic>) to receive cluster upgrade and security notifications."
  type        = string
  default     = null
}

variable "labels" {
  description = "Additional resource labels to apply to the cluster and node pools."
  type        = map(string)
  default     = {}
}

variable "node_pools" {
  description = "Map of managed GKE node pool configurations. Each entry creates a separately managed regional node pool."
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
    general = {
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
}
