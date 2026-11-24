variable "project_id" {
  type        = string
  description = "Google Cloud project ID where the cluster and environment VPC reside."

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "project_id must be a valid GCP project ID (6-30 lowercase letters, digits, or hyphens)."
  }
}

variable "environment" {
  type        = string
  description = "Deployment environment ('staging' or 'prod'). Maps to the network team's 'apps-<environment>' VPC."

  validation {
    condition     = contains(["staging", "prod"], var.environment)
    error_message = "environment must be either 'staging' or 'prod'."
  }
}

variable "region" {
  type        = string
  description = "US region for the regional GKE cluster (e.g., 'us-central1', 'us-east1', 'us-west1')."

  validation {
    condition     = can(regex("^us-[a-z]+[0-9]+$", var.region))
    error_message = "region must be a valid US Google Cloud region (e.g., 'us-central1')."
  }
}

variable "cluster_name" {
  type        = string
  description = "Name of the GKE Standard cluster."

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,38}[a-z0-9]$", var.cluster_name))
    error_message = "cluster_name must be 2-40 characters, start with a lowercase letter, end with a lowercase alphanumeric character, and contain only lowercase letters, numbers, or hyphens."
  }
}

variable "node_locations" {
  type        = list(string)
  default     = []
  description = "Optional list of zones within the region for cluster nodes. Leave empty to use all zones in the region."
}

variable "master_ipv4_cidr_block" {
  type        = string
  default     = "172.16.0.0/28"
  description = "RFC1918 /28 CIDR block for the GKE control plane VPC peering. Override with a non-overlapping /28 when placing multiple clusters in the same VPC."

  validation {
    condition     = can(cidrhost(var.master_ipv4_cidr_block, 0)) && endswith(var.master_ipv4_cidr_block, "/28")
    error_message = "master_ipv4_cidr_block must be a valid /28 IPv4 CIDR block."
  }
}

variable "enable_private_endpoint" {
  type        = bool
  default     = false
  description = "Whether the control plane endpoint is accessible only via private VPC IP. Set to true if all kubectl/CI access goes through VPC/VPN/bastion."
}

variable "gcp_public_cidrs_access_enabled" {
  type        = bool
  default     = false
  description = "Allow Google Cloud public IP ranges to reach the cluster control plane endpoint when private endpoint is disabled."
}

variable "master_authorized_networks" {
  type = list(object({
    cidr_block   = string
    display_name = string
  }))
  default     = []
  description = "List of CIDR blocks authorized to access the Kubernetes control plane API."

  validation {
    condition     = alltrue([for n in var.master_authorized_networks : can(cidrhost(n.cidr_block, 0))])
    error_message = "Every entry in master_authorized_networks must have a valid IPv4 CIDR block."
  }
}

variable "release_channel" {
  type        = string
  default     = "REGULAR"
  description = "GKE release channel for automated control plane and node upgrades ('RAPID', 'REGULAR', or 'STABLE')."

  validation {
    condition     = contains(["RAPID", "REGULAR", "STABLE"], var.release_channel)
    error_message = "release_channel must be one of 'RAPID', 'REGULAR', or 'STABLE'."
  }
}

variable "maintenance_window" {
  type = object({
    start_time = string
    end_time   = string
    recurrence = string
  })
  default = {
    start_time = "2024-01-06T06:00:00Z"
    end_time   = "2024-01-06T12:00:00Z"
    recurrence = "FREQ=WEEKLY;BYDAY=SA,SU"
  }
  description = "Recurring maintenance window for GKE upgrades (RFC3339 start/end timestamps and RRULE recurrence; default is Sat/Sun 06:00-12:00 UTC)."
}

variable "deletion_protection" {
  type        = bool
  default     = true
  description = "Prevents accidental deletion of the GKE cluster via OpenTofu/GCP API."
}

variable "default_max_pods_per_node" {
  type        = number
  default     = 110
  description = "Default maximum number of pods per node (determines secondary Pod IP range sizing per node)."

  validation {
    condition     = var.default_max_pods_per_node >= 8 && var.default_max_pods_per_node <= 256
    error_message = "default_max_pods_per_node must be between 8 and 256."
  }
}

variable "autoscaling_profile" {
  type        = string
  default     = "BALANCED"
  description = "Cluster autoscaler profile ('BALANCED' or 'OPTIMIZE_UTILIZATION')."

  validation {
    condition     = contains(["BALANCED", "OPTIMIZE_UTILIZATION"], var.autoscaling_profile)
    error_message = "autoscaling_profile must be 'BALANCED' or 'OPTIMIZE_UTILIZATION'."
  }
}

variable "gke_security_group" {
  type        = string
  default     = null
  description = "Optional Google Group email (e.g., 'gke-security-groups@example.com') for GKE RBAC integration."
}

variable "database_encryption_key_id" {
  type        = string
  default     = null
  description = "Optional Cloud KMS CryptoKey resource ID for application-layer Kubernetes Secrets encryption."
}

variable "binary_authorization_mode" {
  type        = string
  default     = "DISABLED"
  description = "Binary Authorization evaluation mode ('DISABLED' or 'PROJECT_SINGLETON_POLICY_ENFORCE')."

  validation {
    condition     = contains(["DISABLED", "PROJECT_SINGLETON_POLICY_ENFORCE"], var.binary_authorization_mode)
    error_message = "binary_authorization_mode must be 'DISABLED' or 'PROJECT_SINGLETON_POLICY_ENFORCE'."
  }
}

variable "enable_secret_manager_addon" {
  type        = bool
  default     = true
  description = "Enable the GKE Secret Manager add-on so workloads can mount secrets from Google Cloud Secret Manager via Workload Identity."
}

variable "enable_backup_agent" {
  type        = bool
  default     = true
  description = "Enable the Backup for GKE agent on the cluster."
}

variable "enable_managed_prometheus" {
  type        = bool
  default     = true
  description = "Enable Google Cloud Managed Service for Prometheus."
}

variable "logging_components" {
  type        = list(string)
  default     = ["SYSTEM_COMPONENTS", "WORKLOADS"]
  description = "GKE logging components to send to Cloud Logging."
}

variable "monitoring_components" {
  type        = list(string)
  default     = ["SYSTEM_COMPONENTS", "APISERVER", "SCHEDULER", "CONTROLLER_MANAGER"]
  description = "GKE monitoring components to send to Cloud Monitoring."
}

variable "notification_topic_id" {
  type        = string
  default     = null
  description = "Optional Pub/Sub topic resource ID ('projects/<project>/topics/<topic>') to receive GKE cluster upgrade and security notifications."
}

variable "additional_node_sa_roles" {
  type        = list(string)
  default     = []
  description = "Additional IAM roles to grant to the GKE node service account beyond the least-privilege defaults."
}

variable "labels" {
  type        = map(string)
  default     = {}
  description = "Additional GCP resource labels applied to the cluster."

  validation {
    condition     = alltrue([for k, v in var.labels : can(regex("^[a-z][a-z0-9_-]{0,62}$", k)) && can(regex("^[a-z0-9_-]{0,63}$", v))])
    error_message = "GCP label keys must start with a lowercase letter and keys/values may only contain lowercase letters, numbers, underscores, and hyphens (max 63 chars)."
  }
}

variable "node_pools" {
  type = map(object({
    machine_type           = optional(string, "e2-standard-4")
    disk_size_gb           = optional(number, 100)
    disk_type              = optional(string, "pd-balanced")
    image_type             = optional(string, "COS_CONTAINERD")
    spot                   = optional(bool, false)
    initial_node_count     = optional(number, 1)
    min_node_count         = optional(number, 1)
    max_node_count         = optional(number, 5)
    location_policy        = optional(string, "BALANCED")
    max_surge              = optional(number, 1)
    max_unavailable        = optional(number, 0)
    max_pods_per_node      = optional(number, null)
    node_locations         = optional(list(string), null)
    enable_image_streaming = optional(bool, false)
    labels                 = optional(map(string), {})
    tags                   = optional(list(string), [])
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
      initial_node_count = 1
      min_node_count     = 1
      max_node_count     = 5
      location_policy    = "BALANCED"
    }
  }
  description = "Map of GKE Standard node pools to provision for the cluster. Counts are per-zone across the regional cluster."

  validation {
    condition     = length(var.node_pools) > 0
    error_message = "At least one node pool must be defined in node_pools."
  }

  validation {
    condition     = alltrue([for k, v in var.node_pools : can(regex("^[a-z][a-z0-9-]{0,38}[a-z0-9]$", k))])
    error_message = "Node pool keys must be 2-40 characters, start with a lowercase letter, end with a lowercase alphanumeric character, and contain only lowercase letters, numbers, or hyphens."
  }

  validation {
    condition     = alltrue([for k, v in var.node_pools : v.min_node_count >= 0 && v.max_node_count >= v.min_node_count])
    error_message = "Each node pool must have min_node_count >= 0 and max_node_count >= min_node_count."
  }

  validation {
    condition     = alltrue([for k, v in var.node_pools : contains(["BALANCED", "ANY"], v.location_policy)])
    error_message = "Node pool location_policy must be 'BALANCED' or 'ANY'."
  }

  validation {
    condition = alltrue(flatten([
      for k, v in var.node_pools : [
        for t in v.taints : contains(["NO_SCHEDULE", "PREFER_NO_SCHEDULE", "NO_EXECUTE"], t.effect)
      ]
    ]))
    error_message = "Node taint effect must be 'NO_SCHEDULE', 'PREFER_NO_SCHEDULE', or 'NO_EXECUTE'."
  }
}
