############################################
# Required – what is specific to each cluster
############################################

variable "project_id" {
  description = "Google Cloud project that owns the VPC and will host the cluster."
  type        = string
}

variable "name" {
  description = "Cluster name. Must be unique within the project; also used as a prefix for the node service account."
  type        = string

  validation {
    condition     = can(regex("^[a-z]([-a-z0-9]{0,38}[a-z0-9])?$", var.name))
    error_message = "Name must be 1-40 chars, lowercase letters, digits or hyphens, starting with a letter and not ending with a hyphen."
  }
}

variable "environment" {
  description = "Environment the cluster belongs to. Selects the network team's VPC (apps-<environment>) and GKE subnet."
  type        = string

  validation {
    condition     = contains(["staging", "prod"], var.environment)
    error_message = "Environment must be \"staging\" or \"prod\"."
  }
}

variable "region" {
  description = "US region the cluster runs in (e.g. us-central1). The cluster is regional: control plane and nodes span all zones in the region."
  type        = string

  validation {
    condition     = can(regex("^us-[a-z]+[0-9]$", var.region))
    error_message = "Region must be a US region such as us-central1, us-east1, us-east4 or us-west1."
  }
}

variable "master_authorized_networks" {
  description = <<-EOT
    CIDR blocks allowed to reach the Kubernetes API endpoint (office egress, VPN, CI runners, bastion...).
    Nodes are private; the API has a public endpoint that is reachable ONLY from these ranges and from inside the VPC.
    Required so a cluster is never created with an open API server; pass an empty list to allow access from the VPC only.
  EOT
  type = list(object({
    cidr_block   = string
    display_name = string
  }))

  validation {
    condition     = alltrue([for n in var.master_authorized_networks : can(cidrhost(n.cidr_block, 0))])
    error_message = "Every entry must have a valid CIDR block (e.g. 203.0.113.0/24)."
  }

  validation {
    condition     = alltrue([for n in var.master_authorized_networks : n.cidr_block != "0.0.0.0/0"])
    error_message = "0.0.0.0/0 is not allowed; list the specific ranges that need API access."
  }
}

############################################
# Optional – sensible production defaults
############################################

variable "node_pools" {
  description = <<-EOT
    Node pools to create, keyed by pool name. Every pool is spread across all zones of the region, autoscaled per zone,
    auto-repaired and auto-upgraded, uses Shielded VMs (Secure Boot + integrity monitoring), Container-Optimized OS
    with containerd, and the GKE metadata server (Workload Identity). Override only what a pool needs.
  EOT
  type = map(object({
    machine_type       = optional(string, "e2-standard-4")
    min_nodes_per_zone = optional(number, 1)
    max_nodes_per_zone = optional(number, 5)
    disk_size_gb       = optional(number, 100)
    disk_type          = optional(string, "pd-balanced")
    spot               = optional(bool, false)
    labels             = optional(map(string), {})
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
    error_message = "At least one node pool is required."
  }

  validation {
    condition = alltrue([
      for p in values(var.node_pools) : p.min_nodes_per_zone >= 0 && p.max_nodes_per_zone >= p.min_nodes_per_zone && p.max_nodes_per_zone >= 1
    ])
    error_message = "Each pool needs 0 <= min_nodes_per_zone <= max_nodes_per_zone and max_nodes_per_zone >= 1."
  }

  validation {
    condition = alltrue([
      for p in values(var.node_pools) : alltrue([
        for t in p.taints : contains(["NO_SCHEDULE", "PREFER_NO_SCHEDULE", "NO_EXECUTE"], t.effect)
      ])
    ])
    error_message = "Taint effect must be NO_SCHEDULE, PREFER_NO_SCHEDULE or NO_EXECUTE."
  }
}

variable "release_channel" {
  description = "GKE release channel. REGULAR balances stability and freshness for production; use STABLE for the most conservative upgrades."
  type        = string
  default     = "REGULAR"

  validation {
    condition     = contains(["RAPID", "REGULAR", "STABLE", "EXTENDED"], var.release_channel)
    error_message = "release_channel must be RAPID, REGULAR, STABLE or EXTENDED."
  }
}

variable "maintenance_window" {
  description = "Recurring window in which GKE may perform control plane and node upgrades. Default: every Saturday and Sunday 03:00-11:00 UTC."
  type = object({
    start_time = string # RFC3339 timestamp, only the time-of-day and weekday matter
    end_time   = string
    recurrence = string # RFC5545 RRULE
  })
  default = {
    start_time = "2024-01-06T03:00:00Z"
    end_time   = "2024-01-06T11:00:00Z"
    recurrence = "FREQ=WEEKLY;BYDAY=SA,SU"
  }
}

variable "master_ipv4_cidr_block" {
  description = <<-EOT
    /28 range for the control plane's VPC peering endpoint. Must not overlap anything in the VPC and must be unique per
    cluster in the VPC. Leave null to let GKE allocate the control plane via Private Service Connect (recommended on
    current GKE versions, no range to manage).
  EOT
  type        = string
  default     = null

  validation {
    condition     = var.master_ipv4_cidr_block == null || can(regex("/28$", var.master_ipv4_cidr_block))
    error_message = "master_ipv4_cidr_block must be a /28 CIDR or null."
  }
}

variable "enable_private_endpoint" {
  description = "Disable the public API endpoint entirely; the API is then reachable only from inside the VPC (or peered/VPN networks). Requires in-VPC access for the platform team and CI."
  type        = bool
  default     = false
}

variable "database_encryption_key" {
  description = "Cloud KMS key (projects/.../cryptoKeys/...) used to encrypt Kubernetes secrets at rest in etcd. Null keeps Google-managed encryption."
  type        = string
  default     = null
}

variable "enable_binary_authorization" {
  description = "Enforce the project's Binary Authorization policy on image admission. Enable once the project policy is in place."
  type        = bool
  default     = false
}

variable "deletion_protection" {
  description = "Prevent accidental destruction of the cluster via OpenTofu. Keep enabled for production."
  type        = bool
  default     = true
}

variable "workload_service_accounts" {
  description = <<-EOT
    Google service accounts for product-team workloads, keyed by a short id (used as the account id). Each is bound via
    Workload Identity to one Kubernetes service account and granted the listed project roles, so pods can call Pub/Sub,
    Cloud Storage, Cloud SQL etc. without keys. Example:
      orders-api = { namespace = "orders", kubernetes_service_account = "orders-api",
                     project_roles = ["roles/pubsub.publisher", "roles/cloudsql.client"] }
  EOT
  type = map(object({
    namespace                  = string
    kubernetes_service_account = string
    project_roles              = optional(list(string), [])
  }))
  default = {}

  validation {
    condition     = alltrue([for k, _ in var.workload_service_accounts : can(regex("^[a-z]([-a-z0-9]{4,28}[a-z0-9])$", k))])
    error_message = "Each workload service account key must be 6-30 chars of lowercase letters, digits or hyphens, starting with a letter."
  }
}

variable "labels" {
  description = "Extra resource labels applied to the cluster (merged with environment / managed-by labels)."
  type        = map(string)
  default     = {}
}
