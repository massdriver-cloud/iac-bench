variable "project_id" {
  description = "Project that hosts the clusters and the network team's VPCs."
  type        = string
}

variable "name" {
  description = "Cluster name (lowercase letters, digits, hyphens; max 30 chars)."
  type        = string

  validation {
    condition     = can(regex("^[a-z]([a-z0-9-]{0,28}[a-z0-9])?$", var.name))
    error_message = "name must start with a letter, use only lowercase letters, digits and hyphens, and be at most 30 characters."
  }
}

variable "environment" {
  description = "Environment; selects the VPC (apps-staging or apps-prod)."
  type        = string

  validation {
    condition     = contains(["staging", "prod"], var.environment)
    error_message = "environment must be \"staging\" or \"prod\"."
  }
}

variable "region" {
  description = "US region for the (regional, multi-zone) cluster. Must have a <vpc>-gke-<region> subnet."
  type        = string

  validation {
    condition     = startswith(var.region, "us-")
    error_message = "region must be a US region (us-...)."
  }
}

variable "master_authorized_networks" {
  description = "CIDRs allowed to reach the Kubernetes API endpoint (e.g. VPN/office/CI ranges). Required; the API is never open to the world."
  type = list(object({
    cidr_block   = string
    display_name = string
  }))

  validation {
    condition     = length(var.master_authorized_networks) > 0 && alltrue([for n in var.master_authorized_networks : can(cidrhost(n.cidr_block, 0)) && n.cidr_block != "0.0.0.0/0"])
    error_message = "Provide at least one valid CIDR, and do not use 0.0.0.0/0."
  }
}

variable "enable_private_endpoint" {
  description = "If true the control plane has only a private IP (reachable from the VPC / peered networks)."
  type        = bool
  default     = false
}

variable "release_channel" {
  description = "GKE release channel. Versions and node upgrades are managed by the channel."
  type        = string
  default     = "REGULAR"

  validation {
    condition     = contains(["RAPID", "REGULAR", "STABLE"], var.release_channel)
    error_message = "release_channel must be RAPID, REGULAR or STABLE."
  }
}

variable "maintenance_window" {
  description = "Recurring maintenance window (RFC3339 start/end, RFC5545 recurrence). Default: Saturday/Sunday 04:00-12:00 UTC."
  type = object({
    start_time = string
    end_time   = string
    recurrence = string
  })
  default = {
    start_time = "2024-01-06T04:00:00Z"
    end_time   = "2024-01-06T12:00:00Z"
    recurrence = "FREQ=WEEKLY;BYDAY=SA,SU"
  }
}

variable "node_pools" {
  description = "Node pools keyed by name. Sizes are per zone (regional cluster spans 3 zones). Defaults give one general-purpose autoscaling pool."
  type = map(object({
    machine_type   = optional(string, "e2-standard-4")
    min_node_count = optional(number, 1)
    max_node_count = optional(number, 5)
    disk_size_gb   = optional(number, 100)
    disk_type      = optional(string, "pd-balanced")
    spot           = optional(bool, false)
    labels         = optional(map(string), {})
    taints = optional(list(object({
      key    = string
      value  = string
      effect = string
    })), [])
  }))
  default = { default = {} }

  validation {
    condition     = length(var.node_pools) > 0 && alltrue([for k, p in var.node_pools : p.min_node_count >= 1 && p.max_node_count >= p.min_node_count])
    error_message = "At least one node pool is required; each needs 1 <= min_node_count <= max_node_count (min 1 per zone keeps every zone resilient)."
  }
}

variable "database_encryption_key" {
  description = "Optional Cloud KMS key (full resource ID) for application-layer encryption of Kubernetes secrets. Null disables."
  type        = string
  default     = null
}

variable "deletion_protection" {
  description = "Protect the cluster from accidental deletion."
  type        = bool
  default     = true
}

variable "labels" {
  description = "Extra resource labels applied to the cluster and nodes."
  type        = map(string)
  default     = {}
}
