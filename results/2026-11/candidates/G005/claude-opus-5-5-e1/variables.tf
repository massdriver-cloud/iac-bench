variable "project_id" {
  description = "Project that hosts the shared VPCs (apps-staging / apps-prod) and in which the cluster is created."
  type        = string
}

variable "name" {
  description = "Cluster name. Lowercase letters, digits and hyphens, starting with a letter, max 40 characters (leaves room for derived resource names)."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,38}[a-z0-9]$", var.name))
    error_message = "name must match ^[a-z][a-z0-9-]{0,38}[a-z0-9]$."
  }
}

variable "environment" {
  description = "Environment the cluster belongs to. Selects the VPC: apps-<environment>."
  type        = string

  validation {
    condition     = contains(["staging", "prod"], var.environment)
    error_message = "environment must be one of: staging, prod."
  }
}

variable "region" {
  description = "US region for the (regional) cluster, e.g. us-central1. The subnet apps-<environment>-gke-<region> must exist."
  type        = string

  validation {
    condition     = can(regex("^us-[a-z]+[0-9]+$", var.region))
    error_message = "region must be a US Google Cloud region (us-*)."
  }
}

variable "master_ipv4_cidr_block" {
  description = "RFC1918 /28 for the control plane's private endpoint. Must be unique within the VPC and not overlap any subnet; coordinate with the network team."
  type        = string

  validation {
    condition     = can(cidrhost(var.master_ipv4_cidr_block, 0)) && endswith(var.master_ipv4_cidr_block, "/28")
    error_message = "master_ipv4_cidr_block must be a valid /28 CIDR."
  }
}

variable "master_authorized_networks" {
  description = "CIDRs allowed to reach the control plane's public endpoint (e.g. corporate egress / CI runners). Empty means only from inside the VPC."
  type = list(object({
    cidr_block   = string
    display_name = string
  }))
  default = []

  validation {
    condition     = alltrue([for n in var.master_authorized_networks : can(cidrhost(n.cidr_block, 0))])
    error_message = "Every master_authorized_networks entry needs a valid cidr_block."
  }
}

variable "release_channel" {
  description = "GKE release channel. REGULAR is a good balance for production; STABLE for the most conservative clusters."
  type        = string
  default     = "REGULAR"

  validation {
    condition     = contains(["RAPID", "REGULAR", "STABLE"], var.release_channel)
    error_message = "release_channel must be RAPID, REGULAR or STABLE."
  }
}

variable "maintenance_window" {
  description = "Recurring maintenance window (UTC, RFC3339 times + RFC5545 RRULE). Default: weekend nights, 4h each."
  type = object({
    start_time = string
    end_time   = string
    recurrence = string
  })
  default = {
    start_time = "2024-01-06T02:00:00Z"
    end_time   = "2024-01-06T06:00:00Z"
    recurrence = "FREQ=WEEKLY;BYDAY=SA,SU"
  }
}

variable "node_pools" {
  description = <<-EOT
    Node pools keyed by pool name. Pools are regional: min/max counts are PER ZONE
    (the cluster spans all zones of the region unless node_locations is set).
  EOT
  type = map(object({
    machine_type       = optional(string, "e2-standard-4")
    min_node_count     = optional(number, 1)
    max_node_count     = optional(number, 5)
    initial_node_count = optional(number, 1)
    disk_size_gb       = optional(number, 100)
    disk_type          = optional(string, "pd-balanced")
    spot               = optional(bool, false)
    node_locations     = optional(list(string))
    labels             = optional(map(string), {})
    taints = optional(list(object({
      key    = string
      value  = string
      effect = string
    })), [])
  }))
  default = {
    default = {}
  }

  validation {
    condition     = length(var.node_pools) > 0
    error_message = "At least one node pool is required."
  }

  validation {
    condition = alltrue([
      for p in values(var.node_pools) :
      p.min_node_count >= 0 && p.max_node_count >= p.min_node_count && p.max_node_count > 0
    ])
    error_message = "Each node pool needs 0 <= min_node_count <= max_node_count and max_node_count > 0."
  }

  validation {
    condition = alltrue(flatten([
      for p in values(var.node_pools) : [
        for t in p.taints : contains(["NO_SCHEDULE", "PREFER_NO_SCHEDULE", "NO_EXECUTE"], t.effect)
      ]
    ]))
    error_message = "Taint effect must be NO_SCHEDULE, PREFER_NO_SCHEDULE or NO_EXECUTE."
  }
}

variable "database_encryption_key" {
  description = "Optional Cloud KMS key (projects/.../cryptoKeys/...) for application-layer encryption of Kubernetes Secrets. The GKE service agent needs encrypter/decrypter on it."
  type        = string
  default     = null
}

variable "labels" {
  description = "Extra labels applied to the cluster and nodes."
  type        = map(string)
  default     = {}
}

variable "deletion_protection" {
  description = "Prevent the cluster from being destroyed by tofu. Set to false only right before an intentional teardown."
  type        = bool
  default     = true
}
