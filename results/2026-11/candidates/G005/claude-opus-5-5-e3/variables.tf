variable "project_id" {
  description = "Project that hosts the shared VPCs (apps-staging / apps-prod) and in which the cluster is created."
  type        = string
}

variable "name" {
  description = "Cluster name. Lowercase letters, digits and hyphens, 2-25 characters (also used to derive the node service account ID)."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,23}[a-z0-9]$", var.name))
    error_message = "name must be 2-25 chars, start with a letter, end with a letter or digit, and contain only lowercase letters, digits and hyphens."
  }
}

variable "environment" {
  description = "Environment the cluster belongs to. Selects the VPC (apps-<environment>) and environment-specific defaults such as release channel."
  type        = string

  validation {
    condition     = contains(["staging", "prod"], var.environment)
    error_message = "environment must be either \"staging\" or \"prod\"."
  }
}

variable "region" {
  description = "US region for the (regional) cluster. The subnet apps-<environment>-gke-<region> must already exist."
  type        = string

  validation {
    condition     = can(regex("^us-(central|east|west|south)[0-9]+$", var.region))
    error_message = "region must be a Google Cloud US region, e.g. us-central1, us-east4."
  }
}

variable "release_channel" {
  description = "GKE release channel. Null selects REGULAR for staging and STABLE for prod, so staging receives versions before prod."
  type        = string
  default     = null

  validation {
    condition     = var.release_channel == null || contains(["RAPID", "REGULAR", "STABLE"], coalesce(var.release_channel, "REGULAR"))
    error_message = "release_channel must be RAPID, REGULAR or STABLE (or null for the environment default)."
  }
}

variable "master_authorized_networks" {
  description = "CIDR blocks (internal/VPN ranges) allowed to reach the control plane's private IP endpoint. kubectl access from elsewhere uses the IAM-protected DNS endpoint."
  type = list(object({
    cidr_block   = string
    display_name = string
  }))
  default = []
}

variable "node_pools" {
  description = <<-EOT
    Node pools to create, keyed by pool name. Nodes are spread across all zones of the region.
    min_nodes_per_zone / max_nodes_per_zone bound the autoscaler in each zone.
  EOT
  type = map(object({
    machine_type       = optional(string, "e2-standard-4")
    min_nodes_per_zone = optional(number, 1)
    max_nodes_per_zone = optional(number, 5)
    disk_size_gb       = optional(number, 100)
    disk_type          = optional(string, "pd-balanced")
    spot               = optional(bool, false)
    labels             = optional(map(string), {})
    taints = optional(list(object({
      key    = string
      value  = string
      effect = string
    })), [])
  }))
  default = {
    general = {}
  }

  validation {
    condition     = length(var.node_pools) > 0
    error_message = "At least one node pool is required."
  }

  validation {
    condition     = alltrue([for k, p in var.node_pools : p.min_nodes_per_zone >= 0 && p.max_nodes_per_zone >= p.min_nodes_per_zone && p.max_nodes_per_zone > 0])
    error_message = "Each node pool needs 0 <= min_nodes_per_zone <= max_nodes_per_zone and max_nodes_per_zone > 0."
  }

  validation {
    condition     = alltrue([for k, p in var.node_pools : can(regex("^[a-z][a-z0-9-]{0,38}[a-z0-9]$", k))])
    error_message = "Node pool names must be lowercase letters, digits and hyphens (max 40 chars)."
  }

  validation {
    condition     = alltrue(flatten([for k, p in var.node_pools : [for t in p.taints : contains(["NO_SCHEDULE", "PREFER_NO_SCHEDULE", "NO_EXECUTE"], t.effect)]]))
    error_message = "Taint effect must be NO_SCHEDULE, PREFER_NO_SCHEDULE or NO_EXECUTE."
  }
}

variable "database_encryption_kms_key" {
  description = "Optional Cloud KMS key (projects/.../cryptoKeys/...) for application-layer encryption of Kubernetes Secrets in etcd. The GKE service agent needs encrypter/decrypter on it."
  type        = string
  default     = null
}

variable "maintenance_window" {
  description = "Recurring maintenance window (UTC RFC3339 start/end of one occurrence plus RFC5545 recurrence). Default: Sat and Sun 03:00-11:00 UTC."
  type = object({
    start_time = string
    end_time   = string
    recurrence = string
  })
  default = {
    start_time = "2025-01-04T03:00:00Z"
    end_time   = "2025-01-04T11:00:00Z"
    recurrence = "FREQ=WEEKLY;BYDAY=SA,SU"
  }
}

variable "deletion_protection" {
  description = "Prevent the cluster from being destroyed by OpenTofu. Set false explicitly before decommissioning a cluster."
  type        = bool
  default     = true
}

variable "labels" {
  description = "Additional resource labels applied to the cluster and nodes."
  type        = map(string)
  default     = {}
}
