########################################
# Required - what is specific to each cluster
########################################

variable "project_id" {
  description = "Google Cloud project that holds the network team's VPCs. The cluster, its node pools and its service account are created in this project."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "project_id must be a valid Google Cloud project ID (6-30 chars, lowercase letters, digits and hyphens, starting with a letter)."
  }
}

variable "environment" {
  description = "Environment the cluster belongs to. Selects the VPC owned by the network team (`apps-<environment>`) and the matching GKE subnet."
  type        = string

  validation {
    condition     = contains(["staging", "prod"], var.environment)
    error_message = "environment must be one of: staging, prod."
  }
}

variable "region" {
  description = "US region to create the regional cluster in (e.g. us-central1). The network team's subnet `apps-<environment>-gke-<region>` must exist there."
  type        = string

  validation {
    condition     = can(regex("^us-[a-z]+[0-9]$", var.region))
    error_message = "region must be a US Google Cloud region such as us-central1, us-east1, us-east4, us-west1."
  }
}

variable "cluster_name" {
  description = "Name of the GKE cluster. Must be unique within the project and region."
  type        = string

  validation {
    condition     = can(regex("^[a-z]([-a-z0-9]{0,38}[a-z0-9])?$", var.cluster_name))
    error_message = "cluster_name must be 1-40 characters: lowercase letters, digits and hyphens, starting with a letter and not ending with a hyphen."
  }
}

########################################
# Node pools
########################################

variable "node_pools" {
  description = <<-EOT
    Node pools to create, keyed by pool name. Every pool is regional (spread across all zones of the
    region unless `node_locations` is set), autoscaled, auto-repaired and auto-upgraded, uses the
    dedicated node service account, Shielded VM with Secure Boot, and the GKE metadata server
    (Workload Identity). Only override what differs for a pool. `min_nodes` / `max_nodes` are per zone.
  EOT
  type = map(object({
    machine_type      = optional(string, "e2-standard-4")
    min_nodes         = optional(number, 1)
    max_nodes         = optional(number, 5)
    disk_size_gb      = optional(number, 100)
    disk_type         = optional(string, "pd-balanced")
    image_type        = optional(string, "COS_CONTAINERD")
    spot              = optional(bool, false)
    node_locations    = optional(list(string))
    max_pods_per_node = optional(number, 110)
    max_surge         = optional(number, 1)
    max_unavailable   = optional(number, 0)
    labels            = optional(map(string), {})
    tags              = optional(list(string), [])
    taints = optional(list(object({
      key    = string
      value  = string
      effect = string
    })), [])
  }))
  default = {
    general = {}
  }

  validation {
    condition     = length(var.node_pools) > 0
    error_message = "At least one node pool must be defined."
  }

  validation {
    condition     = alltrue([for k, _ in var.node_pools : can(regex("^[a-z]([-a-z0-9]{0,30}[a-z0-9])?$", k))])
    error_message = "Node pool names must be 1-32 characters: lowercase letters, digits and hyphens, starting with a letter."
  }

  validation {
    condition     = alltrue([for _, p in var.node_pools : p.min_nodes >= 0 && p.max_nodes >= p.min_nodes])
    error_message = "For every node pool, min_nodes must be >= 0 and max_nodes must be >= min_nodes."
  }

  validation {
    condition     = alltrue([for _, p in var.node_pools : contains(["pd-balanced", "pd-ssd", "pd-standard", "hyperdisk-balanced"], p.disk_type)])
    error_message = "disk_type must be one of pd-balanced, pd-ssd, pd-standard, hyperdisk-balanced."
  }

  validation {
    condition     = alltrue([for _, p in var.node_pools : contains(["COS_CONTAINERD", "UBUNTU_CONTAINERD"], p.image_type)])
    error_message = "image_type must be COS_CONTAINERD or UBUNTU_CONTAINERD (both support Shielded nodes and containerd)."
  }

  validation {
    condition = alltrue(flatten([
      for _, p in var.node_pools : [for t in p.taints : contains(["NO_SCHEDULE", "PREFER_NO_SCHEDULE", "NO_EXECUTE"], t.effect)]
    ]))
    error_message = "Taint effect must be NO_SCHEDULE, PREFER_NO_SCHEDULE or NO_EXECUTE."
  }
}

########################################
# Control plane access
########################################

variable "master_authorized_networks" {
  description = <<-EOT
    CIDR blocks allowed to reach the cluster's public control-plane endpoint (e.g. the office/VPN
    egress range or a bastion subnet). Nodes and Pods always reach the control plane over its private
    endpoint inside the VPC. When empty, nothing outside Google Cloud can reach the API server.
  EOT
  type = list(object({
    cidr_block   = string
    display_name = optional(string)
  }))
  default = []

  validation {
    condition     = alltrue([for n in var.master_authorized_networks : can(cidrhost(n.cidr_block, 0))])
    error_message = "Every master_authorized_networks entry must have a valid CIDR block."
  }
}

variable "enable_private_endpoint" {
  description = "Disable the public control-plane endpoint entirely. Only set this when you have VPN/Interconnect or a bastion inside the VPC, otherwise you will lose access to the API server."
  type        = bool
  default     = false
}

variable "master_ipv4_cidr_block" {
  description = <<-EOT
    /28 range for the control plane when GKE creates a VPC-peering based private cluster. Must not
    overlap anything else in the VPC and must be unique per VPC. Leave null for new clusters: GKE 1.29+
    uses Private Service Connect and allocates this automatically.
  EOT
  type        = string
  default     = null

  validation {
    condition     = var.master_ipv4_cidr_block == null || can(regex("/28$", var.master_ipv4_cidr_block)) && can(cidrhost(var.master_ipv4_cidr_block, 0))
    error_message = "master_ipv4_cidr_block must be null or a valid /28 CIDR such as 172.16.0.0/28."
  }
}

########################################
# Lifecycle
########################################

variable "release_channel" {
  description = "GKE release channel. REGULAR balances stability and feature freshness for production; STABLE lags further behind; RAPID is for test clusters only."
  type        = string
  default     = "REGULAR"

  validation {
    condition     = contains(["RAPID", "REGULAR", "STABLE"], var.release_channel)
    error_message = "release_channel must be RAPID, REGULAR or STABLE."
  }
}

variable "maintenance_window" {
  description = <<-EOT
    Weekly recurring window (UTC) in which GKE may perform automatic control-plane and node upgrades.
    `days` uses RRULE day codes (MO, TU, WE, TH, FR, SA, SU). Default: Saturday and Sunday, 03:00-11:00 UTC.
    GKE needs at least 24 hours of total window per 32-day period for upgrades to make progress.
  EOT
  type = object({
    start_time = optional(string, "03:00")
    end_time   = optional(string, "11:00")
    days       = optional(list(string), ["SA", "SU"])
  })
  default = {}

  validation {
    condition = (
      can(regex("^([01][0-9]|2[0-3]):[0-5][0-9]$", var.maintenance_window.start_time)) &&
      can(regex("^([01][0-9]|2[0-3]):[0-5][0-9]$", var.maintenance_window.end_time)) &&
      length(var.maintenance_window.days) > 0 &&
      alltrue([for d in var.maintenance_window.days : contains(["MO", "TU", "WE", "TH", "FR", "SA", "SU"], d)])
    )
    error_message = "maintenance_window start_time/end_time must be HH:MM (24h, UTC) and days must be a non-empty list of MO, TU, WE, TH, FR, SA, SU."
  }
}

variable "deletion_protection" {
  description = "Prevents `tofu destroy` / accidental replacement from deleting the cluster. Keep true for production; set false only when intentionally decommissioning."
  type        = bool
  default     = true
}

########################################
# Security extras
########################################

variable "database_encryption_key" {
  description = "Optional Cloud KMS key (projects/.../cryptoKeys/...) used to encrypt Kubernetes Secrets at rest in etcd (application-layer encryption). The GKE service agent must have roles/cloudkms.cryptoKeyEncrypterDecrypter on it."
  type        = string
  default     = null

  validation {
    condition     = var.database_encryption_key == null || can(regex("^projects/[^/]+/locations/[^/]+/keyRings/[^/]+/cryptoKeys/[^/]+$", var.database_encryption_key))
    error_message = "database_encryption_key must be a full Cloud KMS key resource name: projects/<p>/locations/<l>/keyRings/<r>/cryptoKeys/<k>."
  }
}

variable "enable_binary_authorization" {
  description = "Enforce the project's Binary Authorization policy so only attested/allow-listed images run on the cluster."
  type        = bool
  default     = false
}

variable "labels" {
  description = "Additional resource labels applied to the cluster (and propagated to node VMs). `environment` and `managed-by` are always set."
  type        = map(string)
  default     = {}
}
