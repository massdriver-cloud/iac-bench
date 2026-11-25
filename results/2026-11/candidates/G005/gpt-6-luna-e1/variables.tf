variable "project_id" {
  description = "Google Cloud project containing the cluster and its network."
  type        = string
}

variable "cluster_name" {
  description = "Unique GKE cluster name; keep within 23 characters for the dedicated node service account name."
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,21}[a-z0-9]$", var.cluster_name))
    error_message = "cluster_name must be 3-23 lowercase letters, digits, or hyphens, start with a letter, and end with a letter or digit."
  }
}

variable "region" {
  description = "US region for the regional GKE cluster and its pre-created subnet."
  type        = string
  validation {
    condition     = startswith(var.region, "us-")
    error_message = "This standard is for US regions; region must start with us-."
  }
}

variable "vpc_name" {
  description = "Existing VPC name. The module uses its <vpc>-gke-<region> subnet."
  type        = string
}

variable "master_ipv4_cidr_block" {
  description = "Unused /28 range reserved for the private GKE control plane, non-overlapping with the VPC and connected networks."
  type        = string
}

variable "master_authorized_networks" {
  description = "Optional CIDR allowlist for clients accessing the private control-plane endpoint. Configure only networks with private connectivity to the VPC."
  type = list(object({
    cidr_block   = string
    display_name = string
  }))
  default = []
}

variable "node_pool_name" {
  description = "Name of the managed primary node pool."
  type        = string
  default     = "primary"
}

variable "node_machine_type" {
  description = "Compute Engine machine type for workload nodes."
  type        = string
  default     = "e2-standard-4"
}

variable "node_disk_size_gb" {
  description = "Boot disk size for each node."
  type        = number
  default     = 100
  validation {
    condition     = var.node_disk_size_gb >= 30
    error_message = "node_disk_size_gb must be at least 30 GB."
  }
}

variable "min_nodes_per_zone" {
  description = "Autoscaler minimum node count per zone in this regional node pool."
  type        = number
  default     = 1
  validation {
    condition     = var.min_nodes_per_zone >= 1
    error_message = "min_nodes_per_zone must be at least 1 for production availability."
  }
}

variable "max_nodes_per_zone" {
  description = "Autoscaler maximum node count per zone in this regional node pool."
  type        = number
  default     = 5
  validation {
    condition     = var.max_nodes_per_zone >= var.min_nodes_per_zone
    error_message = "max_nodes_per_zone must be greater than or equal to min_nodes_per_zone."
  }
}

variable "node_locations" {
  description = "Optional explicit list of zones for the regional node pool; null uses all zones in the region."
  type        = list(string)
  default     = null
}

variable "node_labels" {
  description = "Additional Kubernetes node labels."
  type        = map(string)
  default     = {}
}

variable "node_tags" {
  description = "Optional Compute Engine network tags for nodes."
  type        = list(string)
  default     = []
}

variable "cluster_labels" {
  description = "Google Cloud labels applied to the cluster."
  type        = map(string)
  default     = {}
}

variable "deletion_protection" {
  description = "Protect the production cluster from accidental destruction."
  type        = bool
  default     = true
}
