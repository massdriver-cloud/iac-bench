# ---------------------------------------------------------------------------
# Identity / location
# ---------------------------------------------------------------------------

variable "project_id" {
  description = "The Google Cloud project in which the cluster and its VPC live. Mutually exclusive with project."
  type        = string
  default     = null
}

variable "name" {
  description = "Name of the GKE cluster. Used for the GKE cluster resource and as a prefix for node pools."
  type        = string
}

variable "location" {
  description = "Region (or zone, but regions are recommended) in which to create the cluster."
  type        = string
}

variable "network" {
  description = "Name or self_link of the VPC network to deploy the cluster into."
  type        = string
}

variable "subnetwork" {
  description = "Name or self_link of the subnetwork to deploy the cluster into. Expected to be named '<vpc>-gke-<region>' with secondary ranges 'pods' and 'services'."
  type        = string
}

# ---------------------------------------------------------------------------
# Cluster shape
# ---------------------------------------------------------------------------

variable "description" {
  description = "Human-readable description of the cluster."
  type        = string
  default     = "Production GKE cluster managed by the platform team."
}

variable "kubernetes_version" {
  description = "Kubernetes version to use. Use 'latest' (default) to track the release channel, or pin a specific minor (e.g. 1.29.6-gke.1326000)."
  type        = string
  default     = "latest"
}

variable "release_channel" {
  description = "Release channel for the cluster. Production clusters should use REGULAR or STABLE."
  type        = string
  default     = "REGULAR"

  validation {
    condition     = contains(["UNSPECIFIED", "RAPID", "REGULAR", "STABLE"], var.release_channel)
    error_message = "release_channel must be one of UNSPECIFIED, RAPID, REGULAR, or STABLE."
  }
}

variable "enable_intranode_visibility" {
  description = "Enable intranode visibility (flow logs between pods on the same node)."
  type        = bool
  default     = true
}

variable "enable_l4_ilb_subsetting" {
  description = "Enable L4 Internal Load Balancer subsetting for better scale and isolation."
  type        = bool
  default     = true
}

# ---------------------------------------------------------------------------
# Workload identity / security
# ---------------------------------------------------------------------------

variable "workload_identity_enabled" {
  description = "Enable Workload Identity so product workloads can access Pub/Sub, Cloud Storage and Cloud SQL with their own identities. Strongly recommended for production."
  type        = bool
  default     = true
}

variable "enable_binary_authorization" {
  description = "Enforce Binary Authorization (with a default deny policy) for the cluster."
  type        = bool
  default     = true
}

variable "enable_shielded_nodes" {
  description = "Enable Shielded GKE Nodes (default enabled at the GCP level; made explicit here)."
  type        = bool
  default     = true
}

variable "enable_cost_allocation" {
  description = "Enable cost allocation table for granular cost breakdown per namespace/label."
  type        = bool
  default     = true
}

variable "enable_dataplane_v2" {
  description = "Use Dataplane V2 (eBPF-based networking, network policy and better observability)."
  type        = bool
  default     = true
}

# ---------------------------------------------------------------------------
# Maintenance & lifecycle
# ---------------------------------------------------------------------------

variable "maintenance_start_time" {
  description = "Daily maintenance window start time (24-hour HH:MM)."
  type        = string
  default     = "03:00"
}

variable "maintenance_exclusions" {
  description = "List of maintenance exclusion windows. Each object: name, start_time, end_time, exclusion_scope."
  type = list(object({
    name            = string
    start_time      = string
    end_time        = string
    exclusion_scope = optional(string, "NO_UPGRADES")
  }))
  default = []

  validation {
    condition = alltrue([
      for e in var.maintenance_exclusions :
      contains(["NO_UPGRADES", "NO_MINOR_UPGRADES", "NO_MINOR_OR_NODE_UPGRADES"], e.exclusion_scope)
    ])
    error_message = "exclusion_scope must be one of NO_UPGRADES, NO_MINOR_UPGRADES, NO_MINOR_OR_NODE_UPGRADES."
  }
}

variable "deletion_protection" {
  description = "Prevent accidental deletion of the production cluster."
  type        = bool
  default     = true
}

# ---------------------------------------------------------------------------
# Node pools
# ---------------------------------------------------------------------------

variable "system_node_pool" {
  description = "Configuration for the dedicated system node pool (kube-system, monitoring, ingress)."
  type = object({
    name               = optional(string, "system")
    machine_type       = optional(string, "e2-standard-4")
    initial_node_count = optional(number, 1)
    min_count          = optional(number, 1)
    max_count          = optional(number, 3)
    disk_size_gb       = optional(number, 100)
    disk_type          = optional(string, "pd-balanced")
    image_type         = optional(string, "COS_CONTAINERD")
    auto_repair        = optional(bool, true)
    auto_upgrade       = optional(bool, true)
    labels             = optional(map(string), {})
    taints             = optional(list(object({ key = string, value = string, effect = string })), [])
  })
  default = {}
}

variable "workload_node_pools" {
  description = <<-EOT
    Configuration for workload node pools where product team deployments run.
    Map keyed by pool name. Each object:
      machine_type, min_count, max_count, disk_size_gb, disk_type, image_type,
      labels, spot, node_locations. Spot pools default to no autoscaling.
  EOT
  type = map(object({
    machine_type   = optional(string, "e2-standard-4")
    min_count      = optional(number, 1)
    max_count      = optional(number, 6)
    disk_size_gb   = optional(number, 100)
    disk_type      = optional(string, "pd-balanced")
    image_type     = optional(string, "COS_CONTAINERD")
    labels         = optional(map(string), {})
    spot           = optional(bool, false)
    auto_repair    = optional(bool, true)
    auto_upgrade   = optional(bool, true)
    node_locations = optional(list(string), [])
  }))
  default = {}
}

# ---------------------------------------------------------------------------
# Labels
# ---------------------------------------------------------------------------

variable "labels" {
  description = "Labels to apply to the GKE cluster."
  type        = map(string)
  default     = {}
}