# Required Variables (Cluster-specific)

variable "project_id" {
  type        = string
  description = "The GCP project ID where the cluster and network reside."
}

variable "cluster_name" {
  type        = string
  description = "The name of the GKE cluster."
}

variable "region" {
  type        = string
  description = "The GCP region for the regional GKE cluster (e.g. us-central1, us-east4)."
}

variable "network" {
  type        = string
  description = "The VPC network name (e.g. apps-staging or apps-prod)."
}

# Network Configuration Variables (with sensible defaults based on platform conventions)

variable "subnetwork" {
  type        = string
  description = "The name of the subnetwork. Defaults to <vpc>-gke-<region> per network team convention."
  default     = null
}

variable "pods_secondary_range_name" {
  type        = string
  description = "The name of the secondary IP range for Pods."
  default     = "pods"
}

variable "services_secondary_range_name" {
  type        = string
  description = "The name of the secondary IP range for Services."
  default     = "services"
}

# Security and Networking Variables

variable "master_ipv4_cidr_block" {
  type        = string
  description = "The /28 CIDR block for the Kubernetes master private endpoint."
  default     = "172.16.0.0/28"
}

variable "enable_private_endpoint" {
  type        = bool
  description = "Whether the master's internal IP address is used as the cluster endpoint. When false, the public endpoint is reachable (restricted by authorized networks)."
  default     = false
}

variable "enable_master_authorized_networks" {
  type        = bool
  description = "Whether to enforce master authorized networks even if the list is empty."
  default     = false
}

variable "master_authorized_networks" {
  type = list(object({
    cidr_block   = string
    display_name = optional(string)
  }))
  description = "List of CIDR blocks permitted to access the cluster master endpoint."
  default     = []
}

variable "master_authorized_networks_gcp_public_cidrs_access_enabled" {
  type        = bool
  description = "Whether GCP public CIDRs (like Cloud Shell) can access the master endpoint."
  default     = false
}

variable "release_channel" {
  type        = string
  description = "The release channel for GKE automatic upgrades (REGULAR, STABLE, RAPID)."
  default     = "REGULAR"
}

# Maintenance Window Variables

variable "maintenance_start_time" {
  type        = string
  description = "RFC3339 formatted start time for the recurring maintenance window."
  default     = "2024-01-01T04:00:00Z"
}

variable "maintenance_end_time" {
  type        = string
  description = "RFC3339 formatted end time for the recurring maintenance window."
  default     = "2024-01-01T08:00:00Z"
}

variable "maintenance_recurrence" {
  type        = string
  description = "RRULE recurrence string for recurring maintenance window (e.g. weekends)."
  default     = "FREQ=WEEKLY;BYDAY=SA,SU"
}

# Service Account Variables

variable "node_service_account" {
  type        = string
  description = "Existing service account email to use for node pools. If null, a dedicated least-privilege service account is created."
  default     = null
}

variable "node_service_account_id" {
  type        = string
  description = "Custom account_id for the created node service account. If null, derived from cluster_name."
  default     = null
}

# Node Pools Configuration

variable "node_pools" {
  type = map(object({
    machine_type                = optional(string, "e2-standard-4")
    disk_size_gb                = optional(number, 100)
    disk_type                   = optional(string, "pd-balanced")
    image_type                  = optional(string, "COS_CONTAINERD")
    min_count                   = optional(number, 1)
    max_count                   = optional(number, 5)
    initial_node_count          = optional(number, 1)
    location_policy             = optional(string, "BALANCED")
    auto_repair                 = optional(bool, true)
    auto_upgrade                = optional(bool, true)
    max_surge                   = optional(number, 1)
    max_unavailable             = optional(number, 0)
    enable_secure_boot          = optional(bool, true)
    enable_integrity_monitoring = optional(bool, true)
    node_locations              = optional(list(string), null)
    labels                      = optional(map(string), {})
    tags                        = optional(list(string), [])
    metadata                    = optional(map(string), {})
    taints = optional(list(object({
      key    = string
      value  = string
      effect = string
    })), [])
  }))
  description = "Map of node pool configurations. By default, creates a production-ready 'primary-pool'."
  default = {
    "primary-pool" = {
      machine_type = "e2-standard-4"
      min_count    = 1
      max_count    = 5
    }
  }
}

# Operational Variables

variable "deletion_protection" {
  type        = bool
  description = "Whether to protect the GKE cluster from accidental deletion."
  default     = false
}
