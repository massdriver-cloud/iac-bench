############################################
# Required: what is specific to this cluster
############################################

variable "project_id" {
  description = "Google Cloud project that hosts the VPC and in which the cluster is created."
  type        = string
}

variable "region" {
  description = "US region the cluster lives in (regional cluster, e.g. us-central1). The network team's GKE subnet `<vpc>-gke-<region>` must exist here."
  type        = string

  validation {
    condition     = can(regex("^us-[a-z]+[0-9]$", var.region))
    error_message = "region must be a US region such as us-central1, us-east1, us-east4 or us-west1."
  }
}

variable "environment" {
  description = "Environment the cluster belongs to. Selects the network team's VPC (`apps-staging` or `apps-prod`)."
  type        = string

  validation {
    condition     = contains(["staging", "prod"], var.environment)
    error_message = "environment must be either \"staging\" or \"prod\"."
  }
}

variable "cluster_name" {
  description = "Name of the GKE cluster. Must be unique within the project/region."
  type        = string

  validation {
    condition     = can(regex("^[a-z]([-a-z0-9]{0,38}[a-z0-9])?$", var.cluster_name))
    error_message = "cluster_name must start with a letter, contain only lowercase letters, digits and hyphens, and be at most 40 characters."
  }
}

variable "master_authorized_networks" {
  description = <<-EOT
    CIDR ranges allowed to reach the Kubernetes API server (e.g. the corporate VPN, CI runners,
    bastion subnet). Nodes inside the VPC can always reach the control plane. At least one entry is
    required so that the API endpoint is never left open to the internet.
  EOT
  type = list(object({
    cidr_block   = string
    display_name = string
  }))

  validation {
    condition     = length(var.master_authorized_networks) > 0
    error_message = "master_authorized_networks must contain at least one CIDR range; the API server is never exposed to the whole internet."
  }

  validation {
    condition     = alltrue([for n in var.master_authorized_networks : can(cidrhost(n.cidr_block, 0))])
    error_message = "Every master_authorized_networks entry must have a valid cidr_block (e.g. 10.0.0.0/8)."
  }
}

############################################
# Optional: tuned defaults the module owns
############################################

variable "node_pools" {
  description = <<-EOT
    Node pools to create, keyed by pool name. Each pool is spread across the region's zones and
    autoscaled between min_nodes_per_zone and max_nodes_per_zone *per zone*. Omit to get a single
    general-purpose pool. Use `spot = true` plus a taint for fault-tolerant batch work.
  EOT
  type = map(object({
    machine_type       = optional(string, "e2-standard-4")
    min_nodes_per_zone = optional(number, 1)
    max_nodes_per_zone = optional(number, 5)
    disk_size_gb       = optional(number, 100)
    disk_type          = optional(string, "pd-balanced")
    image_type         = optional(string, "COS_CONTAINERD")
    spot               = optional(bool, false)
    node_locations     = optional(list(string), null)
    labels             = optional(map(string), {})
    tags               = optional(list(string), [])
    taints = optional(list(object({
      key    = string
      value  = string
      effect = string
    })), [])
    max_surge       = optional(number, 1)
    max_unavailable = optional(number, 0)
  }))
  default = {
    general = {}
  }

  validation {
    condition     = length(var.node_pools) > 0
    error_message = "At least one node pool must be defined."
  }

  validation {
    condition = alltrue([
      for name, p in var.node_pools : can(regex("^[a-z]([-a-z0-9]{0,38}[a-z0-9])?$", name))
    ])
    error_message = "Node pool names must start with a letter, contain only lowercase letters, digits and hyphens, and be at most 40 characters."
  }

  validation {
    condition = alltrue([
      for name, p in var.node_pools : p.min_nodes_per_zone >= 0 && p.max_nodes_per_zone >= p.min_nodes_per_zone && p.max_nodes_per_zone >= 1
    ])
    error_message = "Each node pool needs 0 <= min_nodes_per_zone <= max_nodes_per_zone and max_nodes_per_zone >= 1."
  }

  validation {
    condition = alltrue([
      for name, p in var.node_pools : contains(["pd-standard", "pd-balanced", "pd-ssd"], p.disk_type)
    ])
    error_message = "disk_type must be one of pd-standard, pd-balanced or pd-ssd."
  }

  validation {
    condition = alltrue(flatten([
      for name, p in var.node_pools : [
        for t in p.taints : contains(["NO_SCHEDULE", "PREFER_NO_SCHEDULE", "NO_EXECUTE"], t.effect)
      ]
    ]))
    error_message = "Taint effect must be one of NO_SCHEDULE, PREFER_NO_SCHEDULE or NO_EXECUTE."
  }
}

variable "release_channel" {
  description = "GKE release channel. REGULAR balances new features with stability and is the production default; use STABLE for the most conservative upgrade cadence."
  type        = string
  default     = "REGULAR"

  validation {
    condition     = contains(["RAPID", "REGULAR", "STABLE"], var.release_channel)
    error_message = "release_channel must be RAPID, REGULAR or STABLE."
  }
}

variable "maintenance_window" {
  description = "Recurring window in which GKE may perform automatic control-plane and node upgrades. Defaults to Saturday and Sunday 04:00-08:00 UTC."
  type = object({
    start_time = string
    end_time   = string
    recurrence = string
  })
  default = {
    start_time = "2024-01-06T04:00:00Z"
    end_time   = "2024-01-06T08:00:00Z"
    recurrence = "FREQ=WEEKLY;BYDAY=SA,SU"
  }
}

variable "master_ipv4_cidr_block" {
  description = <<-EOT
    Optional /28 range for the control plane. Leave null (recommended) and GKE provisions the control
    plane behind Private Service Connect without consuming VPC address space. Only set this if the
    network team has reserved a dedicated /28 for this cluster that does not overlap anything in the VPC.
  EOT
  type        = string
  default     = null

  validation {
    condition     = var.master_ipv4_cidr_block == null || can(regex("/28$", var.master_ipv4_cidr_block))
    error_message = "master_ipv4_cidr_block must be a /28 CIDR block when set."
  }
}

variable "enable_private_endpoint" {
  description = "When true the API server is reachable only from inside the VPC (and peered/VPN-connected networks), with no public IP at all. Requires VPN or a bastion for kubectl."
  type        = bool
  default     = false
}

variable "control_plane_webhook_ports" {
  description = "Extra TCP ports the control plane may open to nodes, for admission webhooks and operators that listen on ports other than 443 (cert-manager, Istio, etc.). Only applied when master_ipv4_cidr_block is set (with Private Service Connect, GKE manages this itself)."
  type        = list(string)
  default     = ["8443", "9443", "15017"]
}

variable "database_encryption_kms_key" {
  description = "Optional Cloud KMS key (projects/.../cryptoKeys/...) used to encrypt Kubernetes secrets at rest in etcd. The GKE service agent must have roles/cloudkms.cryptoKeyEncrypterDecrypter on it."
  type        = string
  default     = null
}

variable "enable_binary_authorization" {
  description = "Enforce the project's Binary Authorization policy on this cluster so only attested images can run."
  type        = bool
  default     = false
}

variable "deletion_protection" {
  description = "Refuse to destroy the cluster through OpenTofu. Keep enabled for production; set to false only when intentionally decommissioning."
  type        = bool
  default     = true
}

variable "labels" {
  description = "Extra labels applied to the cluster and propagated to nodes."
  type        = map(string)
  default     = {}
}
