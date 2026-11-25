# -----------------------------------------------------------------------------
# Identity / placement — the per-cluster specifics the platform team fills in.
# -----------------------------------------------------------------------------

variable "cluster_name" {
  type        = string
  description = "Name of the GKE cluster (lowercase, RFC 1123, max 40 chars). E.g. \"apps-prod-main\"."

  validation {
    condition     = can(regex("^[a-z]([-a-z0-9]*[a-z0-9])?$", var.cluster_name)) && length(var.cluster_name) <= 40
    error_message = "cluster_name must be lowercase letters, digits and hyphens, start with a letter, end with a letter or digit, and be at most 40 characters."
  }
}

variable "project_id" {
  type        = string
  default     = null
  description = "Google Cloud project that owns the cluster and the environment VPC. Leave null to use the project the provider is configured for (GOOGLE_PROJECT environment variable or the credentials file), which is the usual setup: one project per shared environment."
}

variable "region" {
  type        = string
  description = "Google Cloud region for the regional cluster, e.g. \"us-central1\". The network team must have created the <vpc_name>-gke-<region> subnet there."

  validation {
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]$", var.region))
    error_message = "region must look like a Google Cloud region name, e.g. \"us-central1\"."
  }
}

variable "vpc_name" {
  type        = string
  description = "Name of the environment VPC owned by the network team, e.g. \"apps-staging\" or \"apps-prod\". The module derives the subnet name as \"<vpc_name>-gke-<region>\" and uses the \"pods\" and \"services\" secondary ranges, per the network team's naming convention."

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.vpc_name))
    error_message = "vpc_name must be lowercase letters, digits and hyphens, start with a letter and end with a letter or digit."
  }
}

variable "labels" {
  type        = map(string)
  default     = {}
  description = "Extra resource labels applied to the cluster (merged with the module's own managed-by label)."
}

# -----------------------------------------------------------------------------
# Control plane
# -----------------------------------------------------------------------------

variable "release_channel" {
  type        = string
  default     = "REGULAR"
  description = "GKE release channel. REGULAR is the module default: well-tested versions with timely security patches. Use STABLE for a more conservative cadence."

  validation {
    condition     = contains(["RAPID", "REGULAR", "STABLE"], var.release_channel)
    error_message = "release_channel must be one of: RAPID, REGULAR, STABLE."
  }
}

variable "kubernetes_version" {
  type        = string
  default     = null
  description = "Optional minimum Kubernetes version for the control plane (e.g. \"1.30\"). Leave null to track the current version of the release channel."
}

variable "master_ipv4_cidr_block" {
  type        = string
  default     = null
  description = "Optional /28 CIDR for the private control plane. Leave null and GKE will pick one automatically (recommended — avoids collisions between clusters sharing a VPC)."

  validation {
    condition     = var.master_ipv4_cidr_block == null || endswith(var.master_ipv4_cidr_block, "/28")
    error_message = "master_ipv4_cidr_block must be a /28 CIDR block (or null to let GKE choose)."
  }
}

variable "master_authorized_networks" {
  type = list(object({
    cidr_block   = string
    display_name = string
  }))
  description = "CIDR blocks allowed to reach the Kubernetes API server. The module always enforces authorized networks on production clusters; the default allows only RFC 1918 space, i.e. traffic arriving over Cloud VPN / Cloud Interconnect / internal networks."
  default = [
    {
      cidr_block   = "10.0.0.0/8"
      display_name = "rfc1918-10 (internal networks)"
    },
    {
      cidr_block   = "172.16.0.0/12"
      display_name = "rfc1918-172 (internal networks)"
    },
    {
      cidr_block   = "192.168.0.0/16"
      display_name = "rfc1918-192 (internal networks)"
    },
  ]

  validation {
    condition     = length(var.master_authorized_networks) > 0
    error_message = "At least one master authorized network is required so the control plane is never left open."
  }
}

variable "maintenance_start_time_utc" {
  type        = string
  default     = "2024-01-06T08:00:00Z"
  description = "Start of the weekly maintenance window (RFC 3339, UTC). The time-of-day is what matters; the day of week is set by maintenance_recurrence. Default is 08:00 UTC, which is overnight in US regions."
}

variable "maintenance_end_time_utc" {
  type        = string
  default     = "2024-01-06T16:00:00Z"
  description = "End of the weekly maintenance window (RFC 3339, UTC). Default pairs with the 08:00 UTC start for an 8 hour window."
}

variable "maintenance_recurrence" {
  type        = string
  default     = "FREQ=WEEKLY;BYDAY=SA"
  description = "RRULE selecting when the maintenance window recurs. Default: every Saturday (the default window dates fall on a Saturday, keeping everything consistent)."
}

variable "database_encryption_kms_key" {
  type        = string
  default     = null
  description = "Optional Cloud KMS key (full resource name) used to encrypt Kubernetes Secrets at the application layer. Leave null to use Google's default envelope encryption."
}

variable "upgrade_notifications_topic" {
  type        = string
  default     = null
  description = "Optional Pub/Sub topic that receives cluster upgrade/security notifications — either the topic ID (projects/<p>/topics/<t>) or a short topic name in the cluster's project. Leave null to disable."
}

# -----------------------------------------------------------------------------
# Node pool sizing and shape
# -----------------------------------------------------------------------------

variable "machine_type" {
  type        = string
  default     = "e2-standard-4"
  description = "Machine type for the primary node pool. Counts are per zone; a regional cluster runs nodes in every zone of the region."
}

variable "disk_size_gb" {
  type        = number
  default     = 100
  description = "Boot disk size (GB) for nodes in the primary node pool."
}

variable "disk_type" {
  type        = string
  default     = "pd-balanced"
  description = "Boot disk type for nodes in the primary node pool."

  validation {
    condition     = contains(["pd-balanced", "pd-standard", "pd-ssd"], var.disk_type)
    error_message = "disk_type must be one of: pd-balanced, pd-standard, pd-ssd."
  }
}

variable "autoscaling_min_nodes_per_zone" {
  type        = number
  default     = 1
  description = "Minimum nodes per zone in the primary node pool. With a regional cluster this means at least one node in every zone at all times."

  validation {
    condition     = var.autoscaling_min_nodes_per_zone >= 1
    error_message = "autoscaling_min_nodes_per_zone must be at least 1 so every zone keeps a node available."
  }
}

variable "autoscaling_max_nodes_per_zone" {
  type        = number
  default     = 5
  description = "Maximum nodes per zone the cluster autoscaler may scale the primary node pool to."

  validation {
    condition     = var.autoscaling_max_nodes_per_zone >= var.autoscaling_min_nodes_per_zone
    error_message = "autoscaling_max_nodes_per_zone must be greater than or equal to autoscaling_min_nodes_per_zone."
  }
}

# -----------------------------------------------------------------------------
# Safety rails
# -----------------------------------------------------------------------------

variable "deletion_protection" {
  type        = bool
  default     = false
  description = "When true, OpenTofu/Terraform refuses to destroy the cluster. Enable it once the cluster is in service and day-to-day pipelines are the only thing touching this state."
}
