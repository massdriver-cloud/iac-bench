variable "project_id" {
  type        = string
  description = "The GCP project ID in which to create the GKE cluster and associated resources."
}

variable "cluster_name" {
  type        = string
  description = "The name of the GKE cluster."
}

variable "network" {
  type        = string
  description = "The name of the VPC network (e.g. 'apps-staging' or 'apps-prod')."
}

variable "region" {
  type        = string
  description = "The GCP region where the cluster and subnet are located."
  default     = "us-central1"
}

variable "subnet_name" {
  type        = string
  description = "The name of the subnetwork. If not specified, defaults to '<network>-gke-<region>'."
  default     = null
}

variable "pods_secondary_range_name" {
  type        = string
  description = "The name of the secondary IP range for pods in the subnetwork."
  default     = "pods"
}

variable "services_secondary_range_name" {
  type        = string
  description = "The name of the secondary IP range for services in the subnetwork."
  default     = "services"
}

variable "release_channel" {
  type        = string
  description = "The GKE release channel (RAPID, REGULAR, STABLE, or UNSPECIFIED)."
  default     = "REGULAR"

  validation {
    condition     = contains(["RAPID", "REGULAR", "STABLE", "UNSPECIFIED"], var.release_channel)
    error_message = "Release channel must be one of: RAPID, REGULAR, STABLE, UNSPECIFIED."
  }
}

variable "master_ipv4_cidr_block" {
  type        = string
  description = "The IP range in CIDR notation for the GKE cluster control plane private endpoint."
  default     = "172.16.0.0/28"
}

variable "enable_private_nodes" {
  type        = bool
  description = "Whether nodes have internal IP addresses only."
  default     = true
}

variable "enable_private_endpoint" {
  type        = bool
  description = "Whether the master's internal IP address is used as the cluster endpoint."
  default     = false
}

variable "master_authorized_networks" {
  type = list(object({
    cidr_block   = string
    display_name = optional(string)
  }))
  description = "List of master authorized networks CIDR blocks."
  default     = []
}

variable "deletion_protection" {
  type        = bool
  description = "Whether to enable deletion protection on the cluster."
  default     = false
}

variable "datapath_provider" {
  type        = string
  description = "The desired datapath provider for the cluster. ADVANCED_DATAPATH enables Dataplane V2."
  default     = "ADVANCED_DATAPATH"
}

variable "enable_secure_boot" {
  type        = bool
  description = "Whether Secure Boot is enabled on cluster nodes."
  default     = true
}

variable "create_service_account" {
  type        = bool
  description = "Whether to create a dedicated service account for node pools."
  default     = true
}

variable "service_account" {
  type        = string
  description = "The Google Cloud service account to use for node pools if create_service_account is false."
  default     = null
}

variable "maintenance_start_time" {
  type        = string
  description = "Time in GMT when daily maintenance window begins (formatted HH:MM)."
  default     = "03:00"
}

variable "labels" {
  type        = map(string)
  description = "Map of labels to apply to cluster and nodes."
  default     = {}
}

variable "node_pools" {
  type = map(object({
    machine_type       = optional(string, "e2-standard-4")
    min_count          = optional(number, 1)
    max_count          = optional(number, 5)
    initial_node_count = optional(number, 1)
    disk_size_gb       = optional(number, 100)
    disk_type          = optional(string, "pd-balanced")
    auto_repair        = optional(bool, true)
    auto_upgrade       = optional(bool, true)
    preemptible        = optional(bool, false)
    spot               = optional(bool, false)
    labels             = optional(map(string), {})
    node_tags          = optional(list(string), [])
    taints = optional(list(object({
      key    = string
      value  = string
      effect = string
    })), [])
  }))
  description = "Map of node pool configurations for the cluster."
  default = {
    "default-pool" = {
      machine_type = "e2-standard-4"
      min_count    = 1
      max_count    = 5
      disk_size_gb = 100
      disk_type    = "pd-balanced"
      auto_repair  = true
      auto_upgrade = true
    }
  }
}
