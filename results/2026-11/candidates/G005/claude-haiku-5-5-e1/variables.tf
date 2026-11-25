variable "project_id" {
  description = "Google Cloud project that holds both the network (apps-staging / apps-prod VPCs) and the cluster."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "project_id must be a valid Google Cloud project ID."
  }
}

variable "cluster_name" {
  description = "Name of the GKE cluster. Also used as a prefix for the node service account ID, so keep it at most 24 characters."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,22}[a-z0-9]$", var.cluster_name))
    error_message = "cluster_name must be 2-24 chars, lowercase letters, digits and hyphens, starting with a letter and not ending with a hyphen."
  }
}

variable "region" {
  description = "US region for the regional cluster (for example us-central1). The GKE subnet must already exist as <vpc>-gke-<region>."
  type        = string

  validation {
    condition     = can(regex("^us-[a-z]+[0-9]$", var.region))
    error_message = "region must be a US region such as us-central1 or us-east4."
  }
}

variable "environment" {
  description = "Environment the cluster belongs to. Selects the network team's VPC (apps-<environment>) and enables production guardrails."
  type        = string

  validation {
    condition     = contains(["staging", "prod"], var.environment)
    error_message = "environment must be either \"staging\" or \"prod\"."
  }
}

variable "master_ipv4_cidr_block" {
  description = "/28 range for the GKE control plane. Must not overlap any VPC subnet, pod, or service range."
  type        = string

  validation {
    condition     = can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}/28$", var.master_ipv4_cidr_block))
    error_message = "master_ipv4_cidr_block must be an IPv4 /28 CIDR."
  }
}

variable "master_authorized_networks" {
  description = "CIDR blocks allowed to reach the Kubernetes API (for example CI runners and the platform team's VPN egress). At least one is required."
  type = list(object({
    cidr_block   = string
    display_name = string
  }))

  validation {
    condition     = length(var.master_authorized_networks) >= 1
    error_message = "At least one master_authorized_networks entry is required."
  }
}

variable "enable_private_endpoint" {
  description = "If true, the control plane is reachable only from inside the VPC. Leave false unless the platform team has VPC-internal access to the API (bastion, VPN, or CI runners inside the VPC)."
  type        = bool
  default     = false
}

variable "release_channel" {
  description = "GKE release channel. STABLE is recommended for production; RAPID is rejected for prod."
  type        = string
  default     = "REGULAR"

  validation {
    condition     = contains(["RAPID", "REGULAR", "STABLE"], var.release_channel)
    error_message = "release_channel must be RAPID, REGULAR, or STABLE."
  }
}

variable "maintenance_window" {
  description = "Recurring maintenance window for control plane and node upgrades. Times are UTC RFC3339 timestamps; only the time-of-day is used by GKE, and the duration must be at least 4 hours."
  type = object({
    start_time = string
    end_time   = string
    recurrence = string
  })
  default = {
    start_time = "2024-01-06T02:00:00Z"
    end_time   = "2024-01-06T10:00:00Z"
    recurrence = "FREQ=WEEKLY;BYDAY=SA,SU"
  }
}

variable "node_pools" {
  description = <<-EOT
    Node pools to create, keyed by pool name. Every pool is regional: min/max nodes are PER ZONE.
    The module always removes the default pool, so at least one pool should be defined.
    Pools use COS_CONTAINERD, shielded nodes, GKE metadata server (Workload Identity), and auto-repair/auto-upgrade.
  EOT
  type = map(object({
    machine_type    = optional(string, "e2-standard-4")
    disk_size_gb    = optional(number, 100)
    disk_type       = optional(string, "pd-balanced")
    min_nodes       = optional(number, 1)
    max_nodes       = optional(number, 3)
    spot            = optional(bool, false)
    max_surge       = optional(number, 1)
    max_unavailable = optional(number, 0)
    labels          = optional(map(string), {})
    taints = optional(list(object({
      key    = string
      value  = string
      effect = string
    })), [])
  }))
  default = {
    "default-pool" = {}
  }

  validation {
    condition     = length(var.node_pools) >= 1
    error_message = "At least one node pool must be defined."
  }

  validation {
    condition = alltrue([
      for k, p in var.node_pools : p.min_nodes >= 0 && p.max_nodes >= p.min_nodes && p.max_nodes >= 1
    ])
    error_message = "Each node pool needs min_nodes >= 0 and max_nodes >= max(1, min_nodes)."
  }

  validation {
    condition = alltrue([
      for k, p in var.node_pools : can(regex("^[a-z][a-z0-9-]{0,38}[a-z0-9]$", k))
    ])
    error_message = "Node pool names must be lowercase letters, digits and hyphens (max 40 chars), starting with a letter."
  }

  validation {
    condition = alltrue([
      for k, p in var.node_pools : p.disk_size_gb >= 30 && contains(["pd-balanced", "pd-ssd", "pd-standard"], p.disk_type)
    ])
    error_message = "Node pools need disk_size_gb >= 30 and disk_type of pd-balanced, pd-ssd or pd-standard."
  }

  validation {
    condition = alltrue([
      for k, p in var.node_pools : alltrue([for t in p.taints : contains(["NO_SCHEDULE", "PREFER_NO_SCHEDULE", "NO_EXECUTE"], t.effect)])
    ])
    error_message = "Taint effect must be NO_SCHEDULE, PREFER_NO_SCHEDULE, or NO_EXECUTE."
  }
}

variable "deletion_protection" {
  description = "Prevents accidental deletion of the cluster. Keep true; set false only for a deliberate teardown."
  type        = bool
  default     = true
}

variable "database_encryption_key" {
  description = "Optional Cloud KMS key ID (projects/.../cryptoKeys/...) used to encrypt Kubernetes Secrets in etcd at the application layer. Null leaves the Google-managed default."
  type        = string
  default     = null
}

variable "labels" {
  description = "Additional resource labels applied to the cluster, node pools, and node service account where supported."
  type        = map(string)
  default     = {}
}
