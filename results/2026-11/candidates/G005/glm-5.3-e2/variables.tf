# ===========================================================================
# Required inputs -- the only decisions the platform team must make per
# cluster. Everything else has a production-grade default.
# ===========================================================================

variable "project_id" {
  description = "Google Cloud project that hosts the cluster. This must be the same project that owns the environment's VPC (apps-staging / apps-prod)."
  type        = string
}

variable "name" {
  description = "Name of the cluster. Also used to derive the cluster's node service account id (gke-<name>), so it must be 3-26 characters, start with a lowercase letter, contain only lowercase letters, digits and hyphens, and end with a letter or digit."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,24}[a-z0-9]$", var.name))
    error_message = "The name must be 3-26 characters, start with a lowercase letter, contain only lowercase letters, digits and hyphens, and end with a letter or digit."
  }
}

variable "region" {
  description = "Region for the cluster, e.g. us-central1. Clusters are always regional: the control plane and nodes are spread across the region's zones."
  type        = string
}

variable "vpc_name" {
  description = "Name of the network team's VPC to attach the cluster to, e.g. apps-staging or apps-prod."
  type        = string
}

variable "master_ipv4_cidr_block" {
  description = "RFC1918 /28 range dedicated to the cluster's control plane. Must not overlap any subnet or peered range in the VPC, and must be unique per VPC: two clusters attached to the same VPC must not share a control-plane range."
  type        = string

  validation {
    condition = can(cidrnetmask(var.master_ipv4_cidr_block)) && can(regex(
      "^(10\\.|172\\.(1[6-9]|2[0-9]|3[01])|192\\.168\\.)[0-9.]+/28$",
      var.master_ipv4_cidr_block
    ))
    error_message = "master_ipv4_cidr_block must be a valid RFC1918 CIDR in /28 notation, e.g. 172.16.0.0/28."
  }
}

# ===========================================================================
# Networking
# ===========================================================================

variable "subnet_name" {
  description = "Subnet the cluster attaches to. Defaults to the network team's naming convention: <vpc_name>-gke-<region>."
  type        = string
  default     = null
}

variable "pods_secondary_range_name" {
  description = "Name of the subnet's secondary range used for pod IPs. Defaults to the network team's convention."
  type        = string
  default     = "pods"
}

variable "services_secondary_range_name" {
  description = "Name of the subnet's secondary range used for Service cluster IPs. Defaults to the network team's convention."
  type        = string
  default     = "services"
}

variable "enable_private_endpoint" {
  description = "When true (default) the control plane endpoint is only reachable from inside the VPC (VPN, Interconnect, or a bastion in the VPC). Set to false to expose a public endpoint restricted to master_authorized_networks, e.g. to admit a CI/CD runner that cannot reach the VPC."
  type        = bool
  default     = true
}

variable "master_authorized_networks" {
  description = "CIDR blocks allowed to reach the control plane endpoint when it is public, keyed by display name, e.g. { office = \"203.0.113.0/24\" }. Required when enable_private_endpoint is false. Ignored when the endpoint is private."
  type        = map(string)
  default     = {}

  validation {
    condition = alltrue([
      for cidr in values(var.master_authorized_networks) : can(cidrnetmask(cidr))
    ])
    error_message = "Each value of master_authorized_networks must be a valid CIDR block."
  }
}

variable "default_max_pods_per_node" {
  description = "Maximum pods per node for every node pool. GKE's default of 110 burns secondary-range IPs quickly; 32 gives the shared 'pods' range far more headroom on a multi-team cluster. Raise only if individual nodes genuinely need denser pod packing."
  type        = number
  default     = 32

  validation {
    condition     = var.default_max_pods_per_node >= 8 && var.default_max_pods_per_node <= 110
    error_message = "default_max_pods_per_node must be between 8 and 110."
  }
}

# ===========================================================================
# Node pools
# ===========================================================================

variable "node_pools" {
  description = <<-EOT
    Additional node pools for product-team workloads, keyed by node pool name.
    Each entry is a full node pool spec; the module always adds a 'system' pool
    for GKE/Kubernetes system components, and an entry keyed 'system' replaces
    that default. min_count / max_count are autoscaling bounds per zone.

    Example:
      node_pools = {
        general = { machine_type = "e2-standard-8", min_count = 2, max_count = 8 }
        memory  = {
          machine_type = "n2-standard-8"
          taints       = [{ key = "pool", value = "memory", effect = "NoSchedule" }]
        }
        batch = { machine_type = "n2-standard-4", spot = true, min_count = 0, max_count = 20 }
      }
  EOT
  type = map(object({
    machine_type = optional(string, "e2-standard-4")
    min_count    = optional(number, 1)
    max_count    = optional(number, 5)
    disk_size_gb = optional(number, 100)
    disk_type    = optional(string, "pd-balanced")
    spot         = optional(bool, false)
    labels       = optional(map(string), {})
    taints = optional(list(object({
      key    = string
      value  = string
      effect = string
    })), [])
  }))
  default = {}

  validation {
    condition = alltrue([
      for name, pool in var.node_pools :
      can(regex("^[a-z][a-z0-9-]{0,39}$", name))
      && pool.min_count >= 0
      && pool.max_count >= pool.min_count
      && pool.disk_size_gb >= 10
      && contains(["pd-balanced", "pd-ssd", "pd-standard"], pool.disk_type)
      && alltrue([
        for taint in pool.taints : contains(["NoSchedule", "PreferNoSchedule", "NoExecute"], taint.effect)
      ])
    ])
    error_message = "Node pool names must be valid GKE names (lowercase alphanumeric and hyphens), min_count must be <= max_count, disk_size_gb must be >= 10, disk_type must be pd-balanced/pd-ssd/pd-standard, and taint effects must be NoSchedule, PreferNoSchedule or NoExecute."
  }
}

# ===========================================================================
# Upgrades and maintenance
# ===========================================================================

variable "release_channel" {
  description = "GKE release channel for the cluster and all node pools. REGULAR receives patches roughly monthly and is recommended for production."
  type        = string
  default     = "REGULAR"

  validation {
    condition     = contains(["RAPID", "REGULAR", "STABLE"], var.release_channel)
    error_message = "release_channel must be one of RAPID, REGULAR or STABLE."
  }
}

variable "maintenance_window" {
  description = "Recurring window (UTC) during which GKE may perform control-plane maintenance. start and end are 'HH:MM'; recurrence is an RRULE such as 'FREQ=DAILY' or 'FREQ=WEEKLY;BYDAY=SA,SU'. The default is daily 10:00-14:00 UTC, i.e. overnight in the US."
  type = object({
    start      = string
    end        = string
    recurrence = optional(string, "FREQ=DAILY")
  })
  default = {
    start      = "10:00"
    end        = "14:00"
    recurrence = "FREQ=DAILY"
  }

  validation {
    condition = alltrue([
      can(regex("^([01][0-9]|2[0-3]):[0-5][0-9]$", var.maintenance_window.start)),
      can(regex("^([01][0-9]|2[0-3]):[0-5][0-9]$", var.maintenance_window.end)),
      var.maintenance_window.start != var.maintenance_window.end,
    ])
    error_message = "maintenance_window start and end must be HH:MM (UTC) and the window must be non-empty."
  }
}

variable "deletion_protection" {
  description = "Guard against destroying the cluster with `tofu destroy`. The platform team must explicitly set this to false (or remove the resource from configuration) to tear a cluster down."
  type        = bool
  default     = true
}

# ===========================================================================
# Security options
# ===========================================================================

variable "enable_gateway_api" {
  description = "Enable the Kubernetes Gateway API (stable channel) so product teams can manage ingress with Gateway/HTTPRoute resources."
  type        = bool
  default     = true
}

variable "enable_binary_authorization" {
  description = "Require images to be admitted by the project's Binary Authorization policy before they can run. Requires the Binary Authorization API enabled and a policy in the project."
  type        = bool
  default     = false
}

variable "database_encryption_key" {
  description = "Self-link of a Cloud KMS symmetric key used to encrypt Kubernetes Secrets (CMEK). When null, Secrets are encrypted with Google-managed keys. See README for the IAM grant the GKE service agent needs on the key."
  type        = string
  default     = null
}

variable "resource_labels" {
  description = "Labels applied to the cluster resource for inventory/cost allocation, e.g. { team = \"platform\", env = \"prod\" }."
  type        = map(string)
  default     = {}

  validation {
    condition = alltrue([
      for key, value in var.resource_labels :
      can(regex("^[a-z0-9_-]{0,63}$", key)) && can(regex("^[a-z0-9_-]{0,63}$", value))
    ])
    error_message = "resource_labels keys and values must be 0-63 lowercase letters, digits, hyphens or underscores."
  }
}

# ===========================================================================
# Workload Identity
# ===========================================================================

variable "workload_identity_bindings" {
  description = <<-EOT
    Kubernetes service accounts that should impersonate Google service
    accounts via Workload Identity, so workloads can use Pub/Sub, Cloud
    Storage, Cloud SQL and friends without any node-level credentials.
    The map key is the Kubernetes service account name; the entry gives the
    Google service account (which must already exist) and the Kubernetes
    namespace it lives in.

    Example:
      workload_identity_bindings = {
        orders-api = {
          service_account = "orders-api@iacbench-sandbox.iam.gserviceaccount.com"
          namespace       = "orders"
        }
      }
  EOT
  type = map(object({
    service_account = string
    namespace       = string
  }))
  default = {}

  validation {
    condition = alltrue([
      for ksa, binding in var.workload_identity_bindings :
      can(regex("^[a-z][a-z0-9-]{0,62}$", ksa))
      && can(regex("^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$", binding.namespace))
      && can(regex("^[a-z0-9-]+@[a-z0-9.-]+\\.iam\\.gserviceaccount\\.com$", binding.service_account))
    ])
    error_message = "Map keys must be valid Kubernetes service account names; namespace must be a valid DNS label; service_account must be a Google service account email."
  }
}
