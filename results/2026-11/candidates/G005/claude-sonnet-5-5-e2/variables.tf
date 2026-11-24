###############################################################################
# Required inputs: what is specific to each cluster.
###############################################################################

variable "project_id" {
  description = "Project that hosts the cluster. This is the same project that holds the apps-staging / apps-prod VPCs."
  type        = string
}

variable "name" {
  description = "Cluster name (also used as a prefix for the node pool and node service account)."
  type        = string

  validation {
    condition     = can(regex("^[a-z]([a-z0-9-]{0,27}[a-z0-9])?$", var.name))
    error_message = "name must be 1-29 chars: lowercase letters, digits and hyphens, starting with a letter and not ending with a hyphen."
  }
}

variable "environment" {
  description = "Environment the cluster belongs to. Selects the VPC: staging -> apps-staging, prod -> apps-prod."
  type        = string

  validation {
    condition     = contains(["staging", "prod"], var.environment)
    error_message = "environment must be \"staging\" or \"prod\"."
  }
}

variable "region" {
  description = "US region for the cluster. The cluster is regional (control plane and nodes spread across zones) and uses the subnet <vpc>-gke-<region>."
  type        = string

  validation {
    condition     = can(regex("^us-[a-z]+[0-9]+$", var.region))
    error_message = "region must be a US region such as us-central1 or us-east4."
  }
}

variable "master_authorized_networks" {
  description = <<-EOT
    CIDR ranges allowed to reach the Kubernetes API (e.g. office/VPN egress, CI runners, bastion subnet).
    Nodes are always private; this list limits who can reach the control plane endpoint.
    Must not be empty and must not contain 0.0.0.0/0.
  EOT
  type = list(object({
    cidr_block   = string
    display_name = string
  }))

  validation {
    condition     = length(var.master_authorized_networks) > 0
    error_message = "Provide at least one authorized network."
  }

  validation {
    condition     = alltrue([for n in var.master_authorized_networks : n.cidr_block != "0.0.0.0/0"])
    error_message = "0.0.0.0/0 is not allowed in master_authorized_networks."
  }
}

###############################################################################
# Optional inputs with safe production defaults.
###############################################################################

variable "labels" {
  description = "Extra resource labels (e.g. team, cost-center). The environment label is added automatically."
  type        = map(string)
  default     = {}
}

variable "release_channel" {
  description = "GKE release channel. Control plane and nodes are auto-upgraded within it."
  type        = string
  default     = "REGULAR"

  validation {
    condition     = contains(["RAPID", "REGULAR", "STABLE", "EXTENDED"], var.release_channel)
    error_message = "release_channel must be RAPID, REGULAR, STABLE or EXTENDED."
  }
}

variable "maintenance_window" {
  description = "Weekly recurring maintenance window (UTC, RFC3339 start/end of the first occurrence, and RRULE). Default: Saturdays and Sundays 04:00-16:00 UTC."
  type = object({
    start_time = string
    end_time   = string
    recurrence = string
  })
  default = {
    start_time = "2024-01-06T04:00:00Z"
    end_time   = "2024-01-06T16:00:00Z"
    recurrence = "FREQ=WEEKLY;BYDAY=SA,SU"
  }
}

variable "master_ipv4_cidr_block" {
  description = "Optional /28 for the private control plane. Leave null to let GKE choose."
  type        = string
  default     = null
}

variable "node_locations" {
  description = "Optional explicit list of zones for nodes. Null lets GKE use all zones of the region (recommended)."
  type        = list(string)
  default     = null
}

variable "node_pool" {
  description = "Settings of the default (general purpose) node pool. Node counts are PER ZONE; a regional cluster has typically 3 zones."
  type = object({
    machine_type   = optional(string, "e2-standard-4")
    disk_size_gb   = optional(number, 100)
    disk_type      = optional(string, "pd-balanced")
    min_node_count = optional(number, 1)
    max_node_count = optional(number, 5)
    node_labels    = optional(map(string), {})
  })
  default = {}

  validation {
    condition     = var.node_pool.min_node_count >= 1 && var.node_pool.max_node_count >= var.node_pool.min_node_count
    error_message = "node_pool requires 1 <= min_node_count <= max_node_count."
  }
}

variable "deletion_protection" {
  description = "Protect the cluster from accidental deletion. Set to false only when you intend to destroy it."
  type        = bool
  default     = true
}

variable "database_encryption_kms_key" {
  description = "Optional Cloud KMS key (full resource ID) for application-layer encryption of Kubernetes Secrets in etcd. The GKE service agent needs cryptoKeyEncrypterDecrypter on it."
  type        = string
  default     = null
}

variable "enable_binary_authorization" {
  description = "Enforce the project's Binary Authorization policy on the cluster."
  type        = bool
  default     = false
}

variable "node_service_account_extra_roles" {
  description = "Additional project roles for the shared node service account. Prefer granting workload access (Pub/Sub, GCS, Cloud SQL) to Workload Identity principals instead."
  type        = list(string)
  default     = []
}
