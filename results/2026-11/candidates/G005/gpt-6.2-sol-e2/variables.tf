variable "project_id" {
  description = "ID of the Google Cloud project that owns both the cluster and the existing VPC."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "Use a Google Cloud project ID, not a project number or display name."
  }
}

variable "cluster_name" {
  description = "Name for the regional GKE cluster (unique within the project and region)."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-z]([a-z0-9-]{0,38}[a-z0-9])?$", var.cluster_name))
    error_message = "The cluster name must be 1–40 lowercase letters, digits or hyphens, start with a letter, and end with a letter or digit."
  }
}

variable "environment" {
  description = "Selects the existing apps-staging or apps-prod VPC and its GKE subnet."
  type        = string
  nullable    = false

  validation {
    condition     = contains(["staging", "prod"], var.environment)
    error_message = "Environment must be staging or prod."
  }
}

variable "region" {
  description = "US region hosting the pre-created GKE subnet and the regional cluster."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^us-[a-z]+[0-9]+$", var.region))
    error_message = "Use a US region such as us-central1, not a zone."
  }
}

variable "node_zones" {
  description = "Optional set of exactly three distinct zones in the selected region. Null lets GKE select the three zones."
  type        = set(string)
  default     = null

  validation {
    condition     = var.node_zones == null ? true : length(var.node_zones) == 3
    error_message = "Set exactly three node zones or use null for GKE-selected zones."
  }
}

variable "node_pool" {
  description = "Sizing for the on-demand general-purpose Linux pool. Autoscaling bounds are per zone, not cluster totals."
  type = object({
    machine_type       = optional(string, "e2-standard-4")
    disk_size_gb       = optional(number, 100)
    min_nodes_per_zone = optional(number, 1)
    max_nodes_per_zone = optional(number, 4)
  })
  default  = {}
  nullable = false

  validation {
    condition = (
      trimspace(var.node_pool.machine_type) != "" &&
      var.node_pool.disk_size_gb >= 50 && floor(var.node_pool.disk_size_gb) == var.node_pool.disk_size_gb &&
      var.node_pool.min_nodes_per_zone >= 1 && floor(var.node_pool.min_nodes_per_zone) == var.node_pool.min_nodes_per_zone &&
      var.node_pool.max_nodes_per_zone >= var.node_pool.min_nodes_per_zone && floor(var.node_pool.max_nodes_per_zone) == var.node_pool.max_nodes_per_zone
    )
    error_message = "Set a machine type, an integer disk size of at least 50 GB, and integer per-zone bounds satisfying 1 <= min <= max."
  }
}

variable "resource_labels" {
  description = "Extra GKE cluster labels for inventory and cost allocation. The module sets the environment and managed-by labels."
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "secrets_kms_key" {
  description = "Optional full Cloud KMS CryptoKey resource ID for application-layer encryption of Kubernetes Secrets. Use a key in the cluster region and grant the GKE service agent access before applying."
  type        = string
  default     = null
}
