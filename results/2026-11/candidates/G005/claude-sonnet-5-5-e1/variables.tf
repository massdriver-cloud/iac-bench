variable "project_id" {
  description = "Project that hosts both the VPCs and the cluster."
  type        = string
}

variable "name" {
  description = "Cluster name (also prefixes the node pool and node service account)."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,28}[a-z0-9]$", var.name))
    error_message = "name must be 3-30 chars, lowercase letters, digits and hyphens, starting with a letter."
  }
}

variable "environment" {
  description = "Environment; selects the VPC (apps-<environment>)."
  type        = string

  validation {
    condition     = contains(["staging", "prod"], var.environment)
    error_message = "environment must be \"staging\" or \"prod\"."
  }
}

variable "region" {
  description = "US region for the regional cluster. A subnet <vpc>-gke-<region> must exist."
  type        = string

  validation {
    condition = contains([
      "us-central1", "us-east1", "us-east4", "us-east5",
      "us-south1", "us-west1", "us-west2", "us-west3", "us-west4",
    ], var.region)
    error_message = "region must be one of the US regions that have a GKE subnet."
  }
}

variable "master_authorized_networks" {
  description = "CIDR blocks allowed to reach the Kubernetes API (e.g. office/VPN/CI ranges), keyed by a display name. At least one is required; the API server is never open to the internet."
  type        = map(string)

  validation {
    condition     = length(var.master_authorized_networks) > 0
    error_message = "Provide at least one authorized network."
  }
  validation {
    condition     = alltrue([for c in values(var.master_authorized_networks) : can(cidrhost(c, 0)) && c != "0.0.0.0/0"])
    error_message = "Entries must be valid CIDRs and must not be 0.0.0.0/0."
  }
}

variable "release_channel" {
  description = "GKE release channel: REGULAR, STABLE or RAPID. Versions and node upgrades are managed by the channel."
  type        = string
  default     = "REGULAR"

  validation {
    condition     = contains(["RAPID", "REGULAR", "STABLE"], var.release_channel)
    error_message = "release_channel must be RAPID, REGULAR or STABLE."
  }
}

variable "node_machine_type" {
  description = "Machine type of the primary node pool."
  type        = string
  default     = "e2-standard-4"
}

variable "node_disk_size_gb" {
  description = "Boot disk size for nodes."
  type        = number
  default     = 100
}

variable "node_min_count" {
  description = "Minimum nodes PER ZONE (regional clusters use 3 zones by default, so total is 3x)."
  type        = number
  default     = 1

  validation {
    condition     = var.node_min_count >= 1
    error_message = "node_min_count must be at least 1 so every zone stays populated."
  }
}

variable "node_max_count" {
  description = "Maximum nodes PER ZONE."
  type        = number
  default     = 5

  validation {
    condition     = var.node_max_count >= 1
    error_message = "node_max_count must be at least 1."
  }
}

variable "maintenance_start_time" {
  description = "RFC3339 start of the first weekend maintenance window (only time-of-day and weekday matter)."
  type        = string
  default     = "2024-01-06T04:00:00Z"
}

variable "maintenance_end_time" {
  description = "RFC3339 end of the first weekend maintenance window; must be at least 48h of window per Google rules over a week, so default spans Sat 04:00 to Sun 20:00 UTC."
  type        = string
  default     = "2024-01-07T20:00:00Z"
}

variable "database_encryption_key" {
  description = "Optional Cloud KMS key (full resource ID) for application-layer encryption of Kubernetes Secrets in etcd. Null keeps Google-managed encryption."
  type        = string
  default     = null
}

variable "create_cloud_nat" {
  description = "Create a Cloud Router + NAT for the cluster's subnet so private nodes can reach the internet. Leave false if the network team already provides NAT; only one NAT per subnet is allowed."
  type        = bool
  default     = false
}

variable "deletion_protection" {
  description = "Block accidental deletion of the cluster."
  type        = bool
  default     = true
}

variable "labels" {
  description = "Extra resource labels (e.g. team, cost-center)."
  type        = map(string)
  default     = {}
}
