variable "project_id" {
  description = "Google Cloud project that holds the cluster and the network team's VPCs (apps-staging / apps-prod)."
  type        = string
}

variable "name" {
  description = "Cluster name. Lowercase letters, digits and hyphens, 2-40 characters, starts with a letter."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,38}[a-z0-9]$", var.name))
    error_message = "name must be 2-40 characters of lowercase letters, digits and hyphens, starting with a letter and not ending with a hyphen."
  }
}

variable "environment" {
  description = "Environment the cluster belongs to. Selects the network team's VPC (apps-<environment>)."
  type        = string

  validation {
    condition     = contains(["staging", "prod"], var.environment)
    error_message = "environment must be \"staging\" or \"prod\"."
  }
}

variable "region" {
  description = "US region for the regional cluster (control plane and node pools). Must have the network team's GKE subnet apps-<environment>-gke-<region>."
  type        = string

  validation {
    condition     = can(regex("^us-[a-z]+[0-9]$", var.region))
    error_message = "region must be a US region such as us-central1 or us-east1."
  }
}

variable "master_ipv4_cidr_block" {
  description = "/28 range for the GKE control plane peering. Must not overlap any other range in the VPC or peered networks, and must be unique per cluster in the project."
  type        = string

  validation {
    condition     = can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}/28$", var.master_ipv4_cidr_block))
    error_message = "master_ipv4_cidr_block must be an IPv4 /28 CIDR."
  }
}

variable "master_authorized_networks" {
  description = "CIDR ranges allowed to reach the Kubernetes API endpoint (for example office, VPN and CI egress ranges). At least one is required."
  type = list(object({
    cidr_block   = string
    display_name = string
  }))

  validation {
    condition     = length(var.master_authorized_networks) > 0
    error_message = "At least one master_authorized_networks entry is required."
  }
}

variable "enable_private_endpoint" {
  description = "When true, the Kubernetes API is reachable only from inside the VPC (requires VPN/bastion/CI runners inside the network). When false, the public endpoint is reachable only from master_authorized_networks."
  type        = bool
  default     = false
}

variable "release_channel" {
  description = "GKE release channel. REGULAR gives automatic upgrades with a tested version cadence."
  type        = string
  default     = "REGULAR"

  validation {
    condition     = contains(["RAPID", "REGULAR", "STABLE"], var.release_channel)
    error_message = "release_channel must be RAPID, REGULAR or STABLE."
  }
}

variable "maintenance_window" {
  description = "Recurring maintenance window for control plane and node upgrades. Times are RFC 3339 in UTC; the recurrence is an RFC 5545 RRULE. Default: Saturday and Sunday 03:00-11:00 UTC."
  type = object({
    start_time = string
    end_time   = string
    recurrence = string
  })
  default = {
    start_time = "2024-01-06T03:00:00Z"
    end_time   = "2024-01-06T11:00:00Z"
    recurrence = "FREQ=WEEKLY;BYDAY=SA,SU"
  }
}

variable "kms_key_id" {
  description = "Cloud KMS key (full resource ID, projects/.../cryptoKeys/...) used to encrypt Kubernetes Secrets in etcd. Required when environment is prod; null leaves Secrets encrypted only with Google-managed keys."
  type        = string
  default     = null
}

variable "binary_authorization_evaluation_mode" {
  description = "Binary Authorization mode for the cluster. DISABLED or PROJECT_SINGLETON_POLICY_ENFORCE."
  type        = string
  default     = "DISABLED"

  validation {
    condition     = contains(["DISABLED", "PROJECT_SINGLETON_POLICY_ENFORCE"], var.binary_authorization_evaluation_mode)
    error_message = "binary_authorization_evaluation_mode must be DISABLED or PROJECT_SINGLETON_POLICY_ENFORCE."
  }
}

variable "deletion_protection" {
  description = "Prevents the cluster from being destroyed by OpenTofu. Set to false only when deliberately decommissioning a cluster."
  type        = bool
  default     = true
}

variable "node_pools" {
  description = <<-EOT
    Node pools keyed by pool name (lowercase, hyphens, up to 40 characters). Autoscaling counts are per zone:
    a regional cluster spread over three zones runs between 3*min_node_count and 3*max_node_count nodes.
    node_locations optionally restricts a pool to specific zones of the region.
  EOT
  type = map(object({
    machine_type    = optional(string, "e2-standard-4")
    disk_size_gb    = optional(number, 100)
    disk_type       = optional(string, "pd-balanced")
    image_type      = optional(string, "COS_CONTAINERD")
    min_node_count  = optional(number, 1)
    max_node_count  = optional(number, 3)
    node_locations  = optional(list(string))
    node_labels     = optional(map(string), {})
    max_surge       = optional(number, 1)
    max_unavailable = optional(number, 0)
  }))
  default = {
    default = {}
  }

  validation {
    condition     = alltrue([for k, _ in var.node_pools : can(regex("^[a-z][a-z0-9-]{0,38}[a-z0-9]$", k))])
    error_message = "Node pool names must be 2-40 characters of lowercase letters, digits and hyphens, starting with a letter."
  }

  validation {
    condition     = alltrue([for _, p in var.node_pools : p.min_node_count >= 1 && p.min_node_count <= p.max_node_count])
    error_message = "Each node pool needs 1 <= min_node_count <= max_node_count."
  }

  validation {
    condition     = alltrue([for _, p in var.node_pools : p.max_surge >= 0 && p.max_unavailable >= 0 && p.max_surge + p.max_unavailable > 0])
    error_message = "Each node pool needs max_surge + max_unavailable > 0 so upgrades can progress."
  }
}

variable "labels" {
  description = "Additional resource labels applied to the cluster and node pools."
  type        = map(string)
  default     = {}
}
