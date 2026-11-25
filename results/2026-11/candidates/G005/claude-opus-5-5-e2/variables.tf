variable "project_id" {
  description = "Project that hosts the shared VPCs (apps-staging / apps-prod) and in which the cluster is created."
  type        = string
}

variable "name" {
  description = "Cluster name. Lowercase letters, digits and hyphens, starting with a letter."
  type        = string

  validation {
    condition     = can(regex("^[a-z]([-a-z0-9]{0,38}[a-z0-9])?$", var.name))
    error_message = "name must be 1-40 chars of lowercase letters, digits and hyphens, start with a letter and not end with a hyphen."
  }
}

variable "environment" {
  description = "Environment the cluster belongs to. Selects the VPC (apps-<environment>) and environment-specific defaults."
  type        = string

  validation {
    condition     = contains(["staging", "prod"], var.environment)
    error_message = "environment must be \"staging\" or \"prod\"."
  }
}

variable "region" {
  description = "US region for the (regional) cluster, e.g. us-central1. The subnet apps-<environment>-gke-<region> must exist."
  type        = string

  validation {
    condition     = can(regex("^us-[a-z]+[0-9]+$", var.region))
    error_message = "region must be a US region such as us-central1 or us-east4."
  }
}

variable "release_channel" {
  description = "GKE release channel. Defaults to STABLE for prod and REGULAR for staging, so staging sees new versions first."
  type        = string
  default     = null

  validation {
    condition     = var.release_channel == null || contains(["RAPID", "REGULAR", "STABLE"], coalesce(var.release_channel, "STABLE"))
    error_message = "release_channel must be RAPID, REGULAR or STABLE."
  }
}

variable "master_authorized_networks" {
  description = "Extra CIDRs allowed to reach the control plane's IP endpoints. The IP-based endpoint is private-only by default; humans and CI should use the IAM-authenticated DNS endpoint (see the kubectl_dns_endpoint output)."
  type = list(object({
    cidr_block   = string
    display_name = string
  }))
  default = []
}

variable "master_ipv4_cidr_block" {
  description = "Optional /28 for the control plane peering range. Leave null (recommended) to use a Private Service Connect based control plane, which needs no reserved range."
  type        = string
  default     = null
}

variable "maintenance_window" {
  description = "Recurring maintenance window (UTC, RFC 5545 RRULE). Default: Saturday and Sunday 04:00-10:00 UTC."
  type = object({
    start_time = string
    end_time   = string
    recurrence = string
  })
  default = {
    start_time = "2025-01-04T04:00:00Z"
    end_time   = "2025-01-04T10:00:00Z"
    recurrence = "FREQ=WEEKLY;BYDAY=SA,SU"
  }
}

variable "database_encryption_key" {
  description = "Optional Cloud KMS key (projects/.../cryptoKeys/...) for application-layer encryption of Kubernetes Secrets. The GKE service agent needs roles/cloudkms.cryptoKeyEncrypterDecrypter on it."
  type        = string
  default     = null
}

variable "node_pools" {
  description = <<-EOT
    Node pools keyed by name. Autoscaling bounds are per zone (the cluster spans every zone of the region).
    Every attribute is optional; the defaults suit general-purpose workloads.
  EOT
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
  default = {
    general = {}
  }

  validation {
    condition     = length(var.node_pools) > 0
    error_message = "At least one node pool is required."
  }

  validation {
    condition     = alltrue([for k, p in var.node_pools : p.min_node_count >= 0 && p.max_node_count >= p.min_node_count && p.max_node_count > 0])
    error_message = "Each node pool needs 0 <= min_node_count <= max_node_count and max_node_count > 0."
  }

  validation {
    condition     = alltrue([for k, p in var.node_pools : can(regex("^[a-z]([-a-z0-9]{0,30}[a-z0-9])?$", k))])
    error_message = "Node pool names must be lowercase letters, digits and hyphens, starting with a letter."
  }
}

variable "labels" {
  description = "Additional resource labels applied to the cluster and nodes."
  type        = map(string)
  default     = {}
}

variable "deletion_protection" {
  description = "Prevents OpenTofu from destroying the cluster. Set to false and apply before intentionally deleting it."
  type        = bool
  default     = true
}
