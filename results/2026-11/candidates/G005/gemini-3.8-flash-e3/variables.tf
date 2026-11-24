variable "project_id" {
  type        = string
  description = "The Google Cloud project ID hosting the VPC and GKE cluster."
}

variable "cluster_name" {
  type        = string
  description = "The name of the GKE cluster."
}

variable "region" {
  type        = string
  description = "The Google Cloud region where the cluster and subnet are located (e.g., us-central1)."
}

variable "network" {
  type        = string
  description = "The VPC network name (e.g., apps-staging or apps-prod)."
}

variable "subnetwork" {
  type        = string
  description = "The subnetwork name to host the cluster. If null, defaults to '<network>-gke-<region>' as per standard network naming conventions."
  default     = null
}

variable "pods_secondary_range_name" {
  type        = string
  description = "The secondary range name in the subnet used for Kubernetes Pods."
  default     = "pods"
}

variable "services_secondary_range_name" {
  type        = string
  description = "The secondary range name in the subnet used for Kubernetes Services."
  default     = "services"
}

variable "master_ipv4_cidr_block" {
  type        = string
  description = "The /28 IP range in CIDR notation reserved for the GKE control plane."
  default     = "172.16.0.0/28"
}

variable "enable_private_endpoint" {
  type        = bool
  description = "Whether the master's internal IP address is used as the cluster endpoint. If false, master has a public endpoint with authorized network controls, while worker nodes remain strictly private."
  default     = false
}

variable "master_authorized_networks" {
  type = list(object({
    cidr_block   = string
    display_name = optional(string)
  }))
  description = "List of CIDR blocks authorized to reach the cluster master endpoint."
  default     = []
}

variable "release_channel" {
  type        = string
  description = "The GKE release channel for automatic cluster upgrades (RAPID, REGULAR, or STABLE)."
  default     = "REGULAR"
}

variable "maintenance_start_time" {
  type        = string
  description = "Time window specified for daily maintenance operations in GMT (HH:MM format)."
  default     = "04:00"
}

variable "node_pools" {
  type = map(object({
    machine_type = optional(string, "e2-standard-4")
    min_count    = optional(number, 1)
    max_count    = optional(number, 5)
    disk_size_gb = optional(number, 100)
    disk_type    = optional(string, "pd-balanced")
    image_type   = optional(string, "COS_CONTAINERD")
    auto_repair  = optional(bool, true)
    auto_upgrade = optional(bool, true)
    preemptible  = optional(bool, false)
    spot         = optional(bool, false)
    labels       = optional(map(string), {})
    metadata     = optional(map(string), {})
    taints = optional(list(object({
      key    = string
      value  = string
      effect = string
    })), [])
    tags            = optional(list(string), [])
    max_surge       = optional(number, 1)
    max_unavailable = optional(number, 0)
  }))
  description = "Map of node pools to create in the GKE cluster. Defaults to a production-ready general node pool with autoscaling."
  default = {
    "general" = {}
  }
}

variable "node_service_account" {
  type        = string
  description = "Email of an existing Google Service Account to use for GKE nodes. If null, a dedicated least-privilege service account is provisioned by the module."
  default     = null
}

variable "cluster_labels" {
  type        = map(string)
  description = "Resource labels to apply to the GKE cluster."
  default     = {}
}

variable "deletion_protection" {
  type        = bool
  description = "Whether deletion protection is enabled for the GKE cluster."
  default     = true
}

variable "database_encryption_key_name" {
  type        = string
  description = "The Cloud KMS key name used to encrypt Kubernetes Secrets in etcd. If null, secret encryption remains at default GCP encryption at rest."
  default     = null
}
