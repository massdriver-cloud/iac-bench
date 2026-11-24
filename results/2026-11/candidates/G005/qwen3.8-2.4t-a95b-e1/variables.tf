# ---------------------------------------------------------------------------
# Cluster identity — the only things a platform engineer must fill in.
# ---------------------------------------------------------------------------

variable "project_id" {
  description = "Google Cloud project that owns the cluster. Must be the same project as the environment VPC, per our network topology."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "project_id must be a valid Google Cloud project ID: 6-30 lowercase letters, digits and hyphens, starting with a letter."
  }
}

variable "cluster_name" {
  description = "Name of the GKE cluster, e.g. apps-prod-us-central1. It is also used to name the node service account and NAT resources, so keep it short."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,38}[a-z0-9]$", var.cluster_name))
    error_message = "cluster_name must be 2-40 characters of lowercase letters, digits and hyphens, starting with a letter."
  }
}

variable "region" {
  description = "Region for the regional cluster and its node pools, e.g. us-central1. Use one of the US regions where the network team has provisioned a GKE subnet."
  type        = string

  validation {
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]$", var.region))
    error_message = "region must look like a GCP region name, e.g. us-central1."
  }
}

variable "network" {
  description = "Environment VPC owned by the network team, e.g. apps-staging or apps-prod. The GKE subnet inside it is derived as <network>-gke-<region>."
  type        = string
}

# ---------------------------------------------------------------------------
# Networking — defaults follow the conventions the network team already built.
# ---------------------------------------------------------------------------

variable "subnetwork_name" {
  description = "GKE subnet inside the VPC. Defaults to the network team's naming convention <network>-gke-<region>; override only if a subnet deviates."
  type        = string
  default     = null
}

variable "pods_range_name" {
  description = "Name of the subnet secondary range used for pod IPs (network team convention: pods)."
  type        = string
  default     = "pods"
}

variable "services_range_name" {
  description = "Name of the subnet secondary range used for Service cluster IPs (network team convention: services)."
  type        = string
  default     = "services"
}

variable "master_ipv4_cidr_block" {
  description = "RFC1918 /28 for the private control plane. Leave null (platform default) to let GKE auto-select a free /28 — this avoids collisions when several clusters share one VPC."
  type        = string
  default     = null

  validation {
    condition = (
      var.master_ipv4_cidr_block == null ||
      (can(cidrnetmask(var.master_ipv4_cidr_block)) && cidrnetmask(var.master_ipv4_cidr_block) == "255.255.255.240")
    )
    error_message = "master_ipv4_cidr_block must be a /28 CIDR block, e.g. 172.16.0.0/28."
  }
}

variable "enable_private_endpoint" {
  description = "Platform default true: the control plane endpoint is reachable only from inside the VPC. Set to false only if the API must be reachable from outside the VPC, and then master_authorized_networks must be non-empty (enforced by a precondition)."
  type        = bool
  default     = true
}

variable "master_authorized_networks" {
  description = "CIDR blocks allowed to reach the public control plane endpoint (relevant only when enable_private_endpoint = false). Empty by default, which blocks all public access."
  type = list(object({
    display_name = string
    cidr_block   = string
  }))
  default = []

  validation {
    condition     = alltrue([for net in var.master_authorized_networks : can(cidrnetmask(net.cidr_block))])
    error_message = "Every master_authorized_networks entry must have a valid cidr_block."
  }
}

variable "enable_master_global_access" {
  description = "Allow the control plane to be reached from networks peered with the cluster VPC (hub-and-spoke / on-prem topologies). Default false: only the cluster VPC can reach the control plane."
  type        = bool
  default     = false
}

variable "enable_cloud_nat" {
  description = "Provision a Cloud Router + Cloud NAT on the GKE subnet so private nodes can reach the internet (image pulls, package downloads). Disable only if the network team already provides egress for this subnet."
  type        = bool
  default     = true
}

# ---------------------------------------------------------------------------
# Control plane versioning.
# ---------------------------------------------------------------------------

variable "release_channel" {
  description = "GKE release channel. Platform default REGULAR: actively supported without being bleeding edge."
  type        = string
  default     = "REGULAR"

  validation {
    condition     = contains(["RAPID", "REGULAR", "STABLE", "UNSPECIFIED"], var.release_channel)
    error_message = "release_channel must be one of RAPID, REGULAR, STABLE, UNSPECIFIED."
  }
}

variable "kubernetes_version" {
  description = "Pin an exact control plane version. Leave null (platform default) to track the latest valid version in the release channel so clusters stay patched automatically."
  type        = string
  default     = null
}

# ---------------------------------------------------------------------------
# Maintenance and protection.
# ---------------------------------------------------------------------------

variable "maintenance_window" {
  description = "Weekly maintenance window, UTC. Defaults to early-morning weekend."
  type = object({
    start_time = string
    end_time   = string
    days       = list(string)
  })
  default = {
    start_time = "04:00"
    end_time   = "08:00"
    days       = ["SA", "SU"]
  }

  validation {
    condition     = alltrue([for d in var.maintenance_window.days : contains(["MO", "TU", "WE", "TH", "FR", "SA", "SU"], d)])
    error_message = "maintenance_window.days must use two-letter day codes: MO, TU, WE, TH, FR, SA, SU."
  }
}

variable "deletion_protection" {
  description = "Block accidental tofu destroy of the cluster. Default true for production; set to false only to intentionally decommission."
  type        = bool
  default     = true
}

variable "secrets_kms_key" {
  description = "Cloud KMS CryptoKey used for envelope encryption of Kubernetes secrets (CMEK). Leave null for Google-managed encryption. When set, grant the GKE service agent roles/cloudkms.cryptoKeyEncrypterDecrypter on the key."
  type        = string
  default     = null
}

variable "resource_labels" {
  description = "GCP resource labels applied to the cluster, e.g. for cost allocation and asset inventory."
  type        = map(string)
  default     = {}
}

# ---------------------------------------------------------------------------
# Node pools.
# ---------------------------------------------------------------------------

variable "node_pools" {
  description = <<-EOT
    Node pools to create, keyed by pool name. The platform default is a single
    on-demand pool named "default" sized for production. Per-pool settings:
    machine_type, disk_size_gb, disk_type, image_type, spot,
    min_node_count / max_node_count (per zone in the region), service_account
    (defaults to the module-managed node service account), labels, taints.
  EOT
  type = map(object({
    machine_type    = optional(string, "e2-standard-4")
    disk_size_gb    = optional(number, 100)
    disk_type       = optional(string, "pd-balanced")
    image_type      = optional(string, "COS_CONTAINERD")
    spot            = optional(bool, false)
    min_node_count  = optional(number, 1)
    max_node_count  = optional(number, 10)
    service_account = optional(string)
    labels          = optional(map(string), {})
    taints = optional(list(object({
      key    = string
      value  = string
      effect = string
    })), [])
  }))
  default = {
    default = {}
  }

  validation {
    condition     = length(var.node_pools) > 0
    error_message = "A production cluster needs at least one node pool."
  }

  validation {
    condition     = alltrue([for name, pool in var.node_pools : can(regex("^[a-z][a-z0-9-]{0,39}$", name))])
    error_message = "Node pool names must be lowercase letters, digits and hyphens, up to 40 characters, starting with a letter."
  }

  validation {
    condition     = alltrue([for name, pool in var.node_pools : pool.min_node_count >= 0 && pool.max_node_count >= max(pool.min_node_count, 1)])
    error_message = "Each node pool needs min_node_count >= 0 and max_node_count >= max(min_node_count, 1)."
  }

  validation {
    condition = alltrue([
      for name, pool in var.node_pools : alltrue([
        for t in pool.taints : contains(["NO_SCHEDULE", "PREFER_NO_SCHEDULE", "NO_EXECUTE"], t.effect)
      ])
    ])
    error_message = "Taint effects must be one of NO_SCHEDULE, PREFER_NO_SCHEDULE, NO_EXECUTE."
  }
}
