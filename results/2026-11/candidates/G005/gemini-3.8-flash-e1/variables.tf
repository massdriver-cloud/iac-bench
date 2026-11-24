variable "project_id" {
  description = "The Google Cloud project ID hosting the VPC networks and GKE cluster"
  type        = string
}

variable "cluster_name" {
  description = "The name of the GKE Standard cluster"
  type        = string
}

variable "region" {
  description = "The GCP region where the regional GKE cluster and subnet reside (e.g. us-central1)"
  type        = string
}

variable "environment" {
  description = "The deployment environment ('apps-staging' or 'apps-prod', or 'staging' / 'prod')"
  type        = string
}

variable "master_ipv4_cidr_block" {
  description = "The dedicated /28 CIDR block for the GKE hosted master network (must not overlap with any VPC subnet range)"
  type        = string
}

variable "vpc_name" {
  description = "Override for the VPC network name. Defaults to 'apps-<environment>' if null"
  type        = string
  default     = null
}

variable "subnetwork" {
  description = "Override for the subnetwork name. Defaults to '<vpc>-gke-<region>' per network team convention"
  type        = string
  default     = null
}

variable "cluster_secondary_range_name" {
  description = "The name of the secondary subnet range for Kubernetes Pods"
  type        = string
  default     = "pods"
}

variable "services_secondary_range_name" {
  description = "The name of the secondary subnet range for Kubernetes Services"
  type        = string
  default     = "services"
}

variable "release_channel" {
  description = "The GKE release channel for automated Kubernetes upgrades (RAPID, REGULAR, or STABLE)"
  type        = string
  default     = "REGULAR"
  validation {
    condition     = contains(["RAPID", "REGULAR", "STABLE", "UNSPECIFIED"], var.release_channel)
    error_message = "Release channel must be one of: RAPID, REGULAR, STABLE, UNSPECIFIED."
  }
}

variable "maintenance_start_time" {
  description = "Start time for the recurring maintenance window in RFC3339 format (UTC)"
  type        = string
  default     = "2024-01-01T04:00:00Z"
}

variable "maintenance_end_time" {
  description = "End time for the recurring maintenance window in RFC3339 format (UTC)"
  type        = string
  default     = "2024-01-01T08:00:00Z"
}

variable "maintenance_recurrence" {
  description = "Recurrence rule for the recurring maintenance window (RRULE format)"
  type        = string
  default     = "FREQ=WEEKLY;BYDAY=SA,SU"
}

variable "enable_private_endpoint" {
  description = "Whether the master Kubernetes API is only accessible via internal IP addresses. Default false allows authorized public network access."
  type        = bool
  default     = false
}

variable "enable_master_authorized_networks" {
  description = "Whether to enforce master authorized networks even if CIDR list is empty"
  type        = bool
  default     = false
}

variable "master_authorized_networks" {
  description = "External CIDR blocks permitted to reach the Kubernetes master API endpoint"
  type = list(object({
    cidr_block   = string
    display_name = optional(string)
  }))
  default = []
}

variable "master_authorized_networks_gcp_public_cidrs_access_enabled" {
  description = "Whether GCP public CIDR blocks can access the master authorized networks"
  type        = bool
  default     = null
}

variable "enable_gcs_fuse_csi_driver" {
  description = "Enable the Cloud Storage FUSE CSI driver to allow pods to mount GCS buckets directly as volumes"
  type        = bool
  default     = true
}

variable "enable_dns_cache" {
  description = "Enable NodeLocal DNSCache for resilient, low-latency in-cluster DNS resolution"
  type        = bool
  default     = true
}

variable "logging_components" {
  description = "GKE components enabled for Cloud Logging"
  type        = list(string)
  default     = ["SYSTEM_COMPONENTS", "WORKLOADS"]
}

variable "monitoring_components" {
  description = "GKE components enabled for Cloud Monitoring"
  type        = list(string)
  default     = ["SYSTEM_COMPONENTS"]
}

variable "enable_managed_prometheus" {
  description = "Enable Google Cloud Managed Service for Prometheus"
  type        = bool
  default     = true
}

variable "database_encryption_key_name" {
  description = "Optional Cloud KMS key name for encrypting Kubernetes secrets at rest in etcd"
  type        = string
  default     = null
}

variable "deletion_protection" {
  description = "Whether deletion protection is enabled for the cluster to prevent accidental deletion"
  type        = bool
  default     = true
}

variable "cluster_labels" {
  description = "Labels to apply to the GKE cluster resource"
  type        = map(string)
  default     = {}
}

variable "create_service_account" {
  description = "Whether to create a dedicated least-privilege IAM service account for node pools"
  type        = bool
  default     = true
}

variable "service_account_id" {
  description = "Custom account ID for the dedicated node service account (max 30 chars). If null, generated automatically."
  type        = string
  default     = null
}

variable "service_account_email" {
  description = "Existing service account email to use if create_service_account is false"
  type        = string
  default     = null
}

variable "additional_node_sa_roles" {
  description = "Additional IAM roles to grant to the node service account"
  type        = list(string)
  default     = []
}

variable "node_pools" {
  description = "Map of node pool configurations keyed by node pool name"
  type = map(object({
    machine_type       = optional(string, "e2-standard-4")
    min_node_count     = optional(number, 1)
    max_node_count     = optional(number, 5)
    initial_node_count = optional(number, 1)
    disk_size_gb       = optional(number, 100)
    disk_type          = optional(string, "pd-balanced")
    spot               = optional(bool, false)
    image_type         = optional(string, "COS_CONTAINERD")
    node_locations     = optional(list(string), null)
    labels             = optional(map(string), {})
    taints = optional(list(object({
      key    = string
      value  = string
      effect = string
    })), [])
    tags = optional(list(string), [])
  }))
  default = {
    "general" = {
      machine_type       = "e2-standard-4"
      min_node_count     = 1
      max_node_count     = 5
      initial_node_count = 1
      disk_size_gb       = 100
      disk_type          = "pd-balanced"
      spot               = false
      image_type         = "COS_CONTAINERD"
      node_locations     = null
      labels             = {}
      taints             = []
      tags               = []
    }
  }
}
