# ---------------------------------------------------------------------------
# Cluster identity / placement — filled in by the platform team per cluster.
# ---------------------------------------------------------------------------

variable "project_id" {
  description = "GCP project the cluster and its network live in."
  type        = string
}

variable "cluster_name" {
  description = "Name of the GKE cluster. Also reused as the node service account id."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.cluster_name)) && length(var.cluster_name) <= 30
    error_message = "cluster_name must start with a letter, contain only lowercase letters/digits/hyphens, end with a letter/digit, and be at most 30 characters (it is reused as the node service account id)."
  }
}

variable "region" {
  description = "GCP region the regional cluster runs in."
  type        = string
}

variable "network_name" {
  description = "Name of the VPC network (owned by the network team) the cluster attaches to."
  type        = string
}

variable "subnetwork_name" {
  description = "Name of the subnet for GKE. Defaults to the network team's convention '<network_name>-gke-<region>'."
  type        = string
  default     = null
}

# ---------------------------------------------------------------------------
# Node pool sizing — the platform team sizes these for each cluster.
# ---------------------------------------------------------------------------

variable "node_machine_type" {
  description = "Machine type for the default node pool."
  type        = string
  default     = "e2-standard-4"
}

variable "node_min_count" {
  description = "Minimum number of nodes for the default node pool."
  type        = number
  default     = 3
}

variable "node_max_count" {
  description = "Maximum number of nodes for the default node pool."
  type        = number
  default     = 10
}

variable "node_initial_count" {
  description = "Initial node count (>= node_min_count)."
  type        = number
  default     = 3
}

variable "node_disk_size_gb" {
  description = "Boot disk size in GB for nodes."
  type        = number
  default     = 100
}

variable "node_disk_type" {
  description = "Boot disk type for nodes (pd-balanced, pd-ssd)."
  type        = string
  default     = "pd-balanced"
}

variable "node_labels" {
  description = "Kubernetes labels applied to every node in the default pool."
  type        = map(string)
  default     = {}
}

variable "node_taints" {
  description = "Kubernetes taints applied to every node in the default pool."
  type = list(object({
    key    = string
    value  = string
    effect = string
  }))
  default = []
}

variable "additional_node_pools" {
  description = "Optional extra node pools. Keyed by pool name."
  type = map(object({
    machine_type  = string
    min_count     = number
    max_count     = number
    initial_count = number
    disk_size_gb  = optional(number, 100)
    disk_type     = optional(string, "pd-balanced")
    labels        = optional(map(string), {})
    taints = optional(list(object({
      key    = string
      value  = string
      effect = string
    })), [])
  }))
  default = {}
}

# ---------------------------------------------------------------------------
# Release / upgrade behaviour.
# ---------------------------------------------------------------------------

variable "release_channel" {
  description = "GKE release channel: UNSPECIFIED, RAPID, REGULAR or STABLE."
  type        = string
  default     = "REGULAR"
}

variable "node_locations" {
  description = "Zones within the region to place nodes. Empty means use every zone in the region."
  type        = list(string)
  default     = []
}

# ---------------------------------------------------------------------------
# Security knobs.
# ---------------------------------------------------------------------------

variable "master_authorized_networks" {
  description = "CIDR blocks allowed to reach the control-plane endpoint (public endpoint is kept)."
  type = list(object({
    cidr_block   = string
    display_name = string
  }))
  default = []
}

variable "enable_binary_authorization" {
  description = "Enforce Binary Authorization on the cluster (requires the project policy to exist)."
  type        = bool
  default     = false
}

variable "enable_private_nodes" {
  description = "Run nodes with no public IPs (private nodes)."
  type        = bool
  default     = true
}

variable "master_ipv4_cidr_block" {
  description = "CIDR for the private control-plane endpoint (peered into the VPC)."
  type        = string
  default     = "172.16.0.0/28"
}