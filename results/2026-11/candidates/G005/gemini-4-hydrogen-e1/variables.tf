variable "project_id" {
  description = "Google Cloud project ID where both the shared VPC and this GKE cluster reside."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "project_id must be a valid Google Cloud project ID (6-30 lowercase letters, digits, or hyphens)."
  }
}

variable "cluster_name" {
  description = "Unique name for the GKE Standard cluster within the project and region."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,38}[a-z0-9]$", var.cluster_name)) || can(regex("^[a-z]$", var.cluster_name))
    error_message = "cluster_name must be 1-40 characters, start with a lowercase letter, end with an alphanumeric character, and contain only lowercase letters, digits, or hyphens."
  }
}

variable "environment" {
  description = "Deployment environment, used to select the network team's VPC (apps-staging or apps-prod)."
  type        = string

  validation {
    condition     = contains(["staging", "prod"], var.environment)
    error_message = "environment must be either \"staging\" or \"prod\"."
  }
}

variable "region" {
  description = "US Google Cloud region for this regional GKE cluster (e.g., us-central1, us-east1, us-west1)."
  type        = string

  validation {
    condition     = can(regex("^us-[a-z]+[0-9]+$", var.region))
    error_message = "region must be a valid US Google Cloud region (e.g., us-central1, us-east4, us-west1)."
  }
}

variable "node_locations" {
  description = "Optional list of zones within var.region for node placement. Leave empty to let GKE distribute nodes across 3 zones automatically."
  type        = list(string)
  default     = []
}

variable "release_channel" {
  description = "GKE release channel governing Kubernetes version upgrades (RAPID, REGULAR, or STABLE)."
  type        = string
  default     = "REGULAR"

  validation {
    condition     = contains(["RAPID", "REGULAR", "STABLE"], var.release_channel)
    error_message = "release_channel must be one of RAPID, REGULAR, or STABLE."
  }
}

variable "deletion_protection" {
  description = "Enable GCP deletion protection to guard against accidental cluster destruction."
  type        = bool
  default     = true
}

variable "master_ipv4_cidr_block" {
  description = "A /28 RFC1918 CIDR block reserved for the private GKE control plane VPC peering. Must be unique across clusters sharing the same VPC."
  type        = string
  default     = "172.16.0.0/28"

  validation {
    condition     = can(cidrhost(var.master_ipv4_cidr_block, 0)) && endswith(var.master_ipv4_cidr_block, "/28")
    error_message = "master_ipv4_cidr_block must be a valid /28 CIDR block."
  }
}

variable "enable_private_endpoint" {
  description = "If true, disables the public Kubernetes API endpoint so the control plane is only accessible via private VPC/VPN/interconnect."
  type        = bool
  default     = false
}

variable "master_authorized_networks" {
  description = "CIDR blocks allowed to reach the Kubernetes API control plane. Leave empty to block all external public CIDRs."
  type = list(object({
    cidr_block   = string
    display_name = string
  }))
  default = []
}

variable "maintenance_window_start_time" {
  description = "RFC3339 timestamp defining the start of the recurring maintenance window (defaults to 06:00 UTC, off-peak US hours)."
  type        = string
  default     = "2024-01-01T06:00:00Z"
}

variable "maintenance_window_end_time" {
  description = "RFC3339 timestamp defining the end of the recurring maintenance window (must be at least 4 hours after start_time)."
  type        = string
  default     = "2024-01-01T12:00:00Z"
}

variable "maintenance_window_recurrence" {
  description = "RFC5545 RRULE defining how often the maintenance window recurs."
  type        = string
  default     = "FREQ=WEEKLY;BYDAY=SA,SU"
}

variable "autoscaling_profile" {
  description = "Cluster autoscaler profile (BALANCED or OPTIMIZE_UTILIZATION)."
  type        = string
  default     = "BALANCED"

  validation {
    condition     = contains(["BALANCED", "OPTIMIZE_UTILIZATION"], var.autoscaling_profile)
    error_message = "autoscaling_profile must be either BALANCED or OPTIMIZE_UTILIZATION."
  }
}

variable "enable_gcs_fuse_csi_driver" {
  description = "Enable the Cloud Storage FUSE CSI driver so pods can mount GCS buckets as volumes."
  type        = bool
  default     = true
}

variable "enable_vertical_pod_autoscaling" {
  description = "Enable Vertical Pod Autoscaling (VPA) for right-sizing workload requests."
  type        = bool
  default     = true
}

variable "enable_binary_authorization" {
  description = "Enforce Binary Authorization project singleton policy on container images."
  type        = bool
  default     = false
}

variable "etcd_kms_key_id" {
  description = "Optional Cloud KMS CryptoKey resource ID for application-layer encryption of Kubernetes Secrets in etcd."
  type        = string
  default     = null
}

variable "security_group" {
  description = "Optional Google Group email (e.g., gke-security-groups@example.com) for Kubernetes RBAC via Google Groups."
  type        = string
  default     = null
}

variable "notification_pubsub_topic" {
  description = "Optional Pub/Sub topic resource ID (projects/<project>/topics/<topic>) for GKE upgrade and security bulletin notifications."
  type        = string
  default     = null
}

variable "labels" {
  description = "Additional Google Cloud resource labels applied to the cluster and node pools."
  type        = map(string)
  default     = {}
}

variable "node_pools" {
  description = "Map of managed GKE Standard node pools. Defaults to a multi-zone autoscaling general-purpose pool."
  type = map(object({
    machine_type           = optional(string, "e2-standard-4")
    min_node_count         = optional(number, 1)
    max_node_count         = optional(number, 5)
    location_policy        = optional(string, "BALANCED")
    disk_type              = optional(string, "pd-balanced")
    disk_size_gb           = optional(number, 100)
    image_type             = optional(string, "COS_CONTAINERD")
    spot                   = optional(bool, false)
    max_surge              = optional(number, 1)
    max_unavailable        = optional(number, 0)
    node_locations         = optional(list(string), [])
    labels                 = optional(map(string), {})
    tags                   = optional(list(string), [])
    enable_image_streaming = optional(bool, false)
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
    }
  }

  validation {
    condition     = length(var.node_pools) > 0
    error_message = "At least one node pool must be defined in node_pools."
  }

  validation {
    condition = alltrue([
      for _, pool in var.node_pools :
      pool.min_node_count >= 0 && pool.max_node_count >= pool.min_node_count
    ])
    error_message = "Each node pool must have min_node_count >= 0 and max_node_count >= min_node_count."
  }

  validation {
    condition = alltrue([
      for _, pool in var.node_pools :
      contains(["BALANCED", "ANY"], pool.location_policy)
    ])
    error_message = "Each node pool location_policy must be BALANCED or ANY."
  }

  validation {
    condition = alltrue(flatten([
      for _, pool in var.node_pools : [
        for taint in pool.taints :
        contains(["NO_SCHEDULE", "PREFER_NO_SCHEDULE", "NO_EXECUTE"], taint.effect)
      ]
    ]))
    error_message = "Node pool taint effects must be one of NO_SCHEDULE, PREFER_NO_SCHEDULE, or NO_EXECUTE."
  }
}
