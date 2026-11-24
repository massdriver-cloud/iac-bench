variable "project_id" {
  description = "The Google Cloud Project ID in which the cluster will be created."
  type        = string
}

variable "cluster_name" {
  description = "The name of the GKE cluster."
  type        = string
}

variable "region" {
  description = "The Google Cloud region for the cluster."
  type        = string
  default     = "us-central1"
}

variable "environment" {
  description = "The deployment environment (e.g. prod, staging)."
  type        = string
  default     = "prod"
}

variable "network_name" {
  description = "The VPC network name. Defaults to apps-<environment> if null."
  type        = string
  default     = null
}

variable "subnet_name" {
  description = "The subnetwork name. Defaults to <vpc>-gke-<region> if null."
  type        = string
  default     = null
}

variable "ip_range_pods" {
  description = "The secondary range name for pods."
  type        = string
  default     = "pods"
}

variable "ip_range_services" {
  description = "The secondary range name for services."
  type        = string
  default     = "services"
}

variable "enable_private_nodes" {
  description = "Whether nodes have internal IP addresses only."
  type        = bool
  default     = true
}

variable "enable_private_endpoint" {
  description = "Whether master is accessible only via private IP."
  type        = bool
  default     = false
}

variable "master_ipv4_cidr_block" {
  description = "The IP range in CIDR notation for the GKE master surface."
  type        = string
  default     = "172.16.0.0/28"
}

variable "release_channel" {
  description = "The GKE release channel (RAPID, REGULAR, STABLE)."
  type        = string
  default     = "REGULAR"
}

variable "enable_vertical_pod_autoscaling" {
  description = "Enable Vertical Pod Autoscaling for the cluster."
  type        = bool
  default     = true
}

variable "deletion_protection" {
  description = "Whether deletion protection is enabled on the cluster."
  type        = bool
  default     = false
}

variable "master_authorized_networks" {
  description = "List of master authorized networks objects."
  type = list(object({
    cidr_block   = string
    display_name = string
  }))
  default = []
}

variable "maintenance_start_time" {
  description = "Start time for recurring maintenance window (RFC3339 format)."
  type        = string
  default     = "2024-01-01T04:00:00Z"
}

variable "maintenance_end_time" {
  description = "End time for recurring maintenance window (RFC3339 format)."
  type        = string
  default     = "2024-01-01T08:00:00Z"
}

variable "maintenance_recurrence" {
  description = "Recurrence rule for maintenance window (RRULE format)."
  type        = string
  default     = "FREQ=WEEKLY;BYDAY=SA,SU"
}

variable "cluster_resource_labels" {
  description = "Additional labels to apply to the cluster."
  type        = map(string)
  default     = {}
}

variable "node_pools" {
  description = "Map of node pool configurations."
  type = map(object({
    machine_type   = optional(string, "e2-standard-4")
    min_count      = optional(number, 1)
    max_count      = optional(number, 5)
    initial_count  = optional(number, 1)
    disk_size_gb   = optional(number, 100)
    disk_type      = optional(string, "pd-balanced")
    auto_repair    = optional(bool, true)
    auto_upgrade   = optional(bool, true)
    spot           = optional(bool, false)
    labels         = optional(map(string), {})
    tags           = optional(list(string), [])
    node_locations = optional(list(string))
  }))
  default = {
    "default-pool" = {
      machine_type  = "e2-standard-4"
      min_count     = 1
      max_count     = 5
      initial_count = 1
      disk_size_gb  = 100
      disk_type     = "pd-balanced"
      auto_repair   = true
      auto_upgrade  = true
      spot          = false
      labels        = {}
      tags          = []
    }
  }
}
