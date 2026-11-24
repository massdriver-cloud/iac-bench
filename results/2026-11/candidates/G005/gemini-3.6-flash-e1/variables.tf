variable "project_id" {
  type        = string
  description = "The GCP project ID where the GKE cluster will be created."
}

variable "vpc_name" {
  type        = string
  description = "The name of the VPC network (e.g. apps-staging, apps-prod)."
}

variable "cluster_name" {
  type        = string
  description = "The name of the GKE cluster."
}

variable "region" {
  type        = string
  description = "The GCP region for the GKE cluster and subnet."
  default     = "us-central1"
}

variable "subnet_name" {
  type        = string
  description = "The name of the subnetwork. Defaults to <vpc_name>-gke-<region> if null."
  default     = null
}

variable "pods_secondary_range_name" {
  type        = string
  description = "Name of the secondary IPv4 range for pods in the subnet."
  default     = "pods"
}

variable "services_secondary_range_name" {
  type        = string
  description = "Name of the secondary IPv4 range for services in the subnet."
  default     = "services"
}

variable "release_channel" {
  type        = string
  description = "The GKE release channel (RAPID, REGULAR, STABLE)."
  default     = "REGULAR"
}

variable "master_ipv4_cidr_block" {
  type        = string
  description = "IP range in CIDR notation for the GKE master control plane."
  default     = "172.16.0.0/28"
}

variable "enable_private_nodes" {
  type        = bool
  description = "Whether cluster nodes have internal IP addresses only."
  default     = true
}

variable "enable_private_endpoint" {
  type        = bool
  description = "Whether the master internal IP address is used as the cluster endpoint."
  default     = false
}

variable "enable_master_authorized_networks" {
  type        = bool
  description = "Whether to enable master authorized networks."
  default     = false
}

variable "master_authorized_networks" {
  type = list(object({
    cidr_block   = string
    display_name = string
  }))
  description = "List of authorized IPv4 CIDR blocks for control plane access."
  default     = []
}

variable "deletion_protection" {
  type        = bool
  description = "Whether deletion protection is enabled on the GKE cluster."
  default     = true
}

variable "machine_type" {
  type        = string
  description = "Machine type for the primary node pool."
  default     = "e2-standard-4"
}

variable "disk_size_gb" {
  type        = number
  description = "Disk size in GB for nodes in the primary node pool."
  default     = 100
}

variable "disk_type" {
  type        = string
  description = "Disk type for nodes in the primary node pool."
  default     = "pd-balanced"
}

variable "min_node_count" {
  type        = number
  description = "Minimum number of nodes per zone in the primary node pool."
  default     = 1
}

variable "max_node_count" {
  type        = number
  description = "Maximum number of nodes per zone in the primary node pool."
  default     = 5
}

variable "enable_autoscaling" {
  type        = bool
  description = "Whether autoscaling is enabled for the primary node pool."
  default     = true
}

variable "node_count" {
  type        = number
  description = "Fixed node count per zone if autoscaling is disabled."
  default     = 3
}

variable "spot" {
  type        = bool
  description = "Whether to use Spot VMs for the primary node pool."
  default     = false
}

variable "create_service_account" {
  type        = bool
  description = "Whether to create a dedicated Google Service Account for node pools."
  default     = true
}

variable "service_account_name" {
  type        = string
  description = "Custom name for the node service account if created."
  default     = null
}

variable "service_account_email" {
  type        = string
  description = "Existing service account email to use if create_service_account is false."
  default     = null
}

variable "node_labels" {
  type        = map(string)
  description = "Labels to apply to nodes in the primary node pool."
  default     = {}
}

variable "node_tags" {
  type        = list(string)
  description = "Network tags to apply to nodes in the primary node pool."
  default     = []
}

variable "node_pools" {
  type        = map(any)
  description = "Map of additional node pool configurations."
  default     = {}
}

variable "maintenance_start_time" {
  type        = string
  description = "Start time of recurring maintenance window (RFC3339 format)."
  default     = "2024-01-01T04:00:00Z"
}

variable "maintenance_recurrence" {
  type        = string
  description = "Recurrence rule for maintenance window (RRULE format)."
  default     = "FREQ=WEEKLY;BYDAY=SA,SU"
}

variable "datapath_provider" {
  type        = string
  description = "The datapath provider for the cluster (ADVANCED_DATAPATH for Dataplane V2)."
  default     = "ADVANCED_DATAPATH"
}
