variable "project_id" {
  description = "Google Cloud project that hosts the cluster. This is the same project as the network team's apps-<env> VPCs."
  type        = string
}

variable "name" {
  description = "Cluster name. 2-22 characters: lowercase letters, digits and hyphens, starting with a letter and not ending with a hyphen. The 22-character limit keeps the derived node service account ID within GCP's 30-character limit."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,20}[a-z0-9]$", var.name))
    error_message = "name must be 2-22 characters: lowercase letters, digits and hyphens, starting with a letter and ending with a letter or digit."
  }
}

variable "environment" {
  description = "Environment the cluster belongs to. Selects the network team's VPC (apps-<environment>) and its GKE subnet."
  type        = string

  validation {
    condition     = contains(["staging", "prod"], var.environment)
    error_message = "environment must be either \"staging\" or \"prod\"."
  }
}

variable "region" {
  description = "US region for the regional cluster. The control plane and node pools span the region's zones. The GKE subnet <vpc>-gke-<region> must already exist."
  type        = string

  validation {
    condition     = can(regex("^us-(central1|east1|east4|east5|south1|west1|west2|west3|west4)$", var.region))
    error_message = "region must be a US Google Cloud region, for example us-central1 or us-east1."
  }
}

variable "control_plane_cidr" {
  description = "/28 range for the control plane's private endpoint. It must not overlap any range in the VPC or on-premises networks."
  type        = string

  validation {
    condition     = can(cidrhost(var.control_plane_cidr, 0)) && endswith(var.control_plane_cidr, "/28")
    error_message = "control_plane_cidr must be a valid /28 IPv4 CIDR."
  }
}

variable "master_authorized_networks" {
  description = "CIDR ranges allowed to reach the control plane endpoint. The default empty list permits no public access. Use this with enable_private_endpoint = false to keep public access open only for listed ranges."
  type = list(object({
    cidr_block   = string
    display_name = optional(string, "")
  }))
  default = []
}

variable "enable_private_endpoint" {
  description = "When true, the control plane is reachable only through its private IP inside the VPC. When false, it has a public endpoint restricted to master_authorized_networks."
  type        = bool
  default     = false
}

variable "deletion_protection" {
  description = "Prevents the cluster from being destroyed by OpenTofu or the API. Turn this off only for a planned decommission."
  type        = bool
  default     = true
}

variable "release_channel" {
  description = "GKE release channel. Auto-upgrades follow the channel. STABLE is the most conservative and REGULAR is the default."
  type        = string
  default     = "REGULAR"

  validation {
    condition     = contains(["RAPID", "REGULAR", "STABLE"], var.release_channel)
    error_message = "release_channel must be RAPID, REGULAR or STABLE."
  }
}

variable "maintenance_window" {
  description = "Recurring window in which GKE may perform control plane and node upgrades. Times are RFC 3339. The window must be at least 4 hours long."
  type = object({
    start_time = string
    end_time   = string
    recurrence = string
  })
  default = {
    start_time = "2025-01-04T03:00:00Z"
    end_time   = "2025-01-04T09:00:00Z"
    recurrence = "FREQ=WEEKLY;BYDAY=SA"
  }
}

variable "node_pools" {
  description = <<-EOT
    Node pools keyed by pool name. Each pool is a regional node pool that autoscales between min and max nodes per zone. Nodes run COS with secure boot, Workload Identity and a dedicated service account. Set spot = true only for fault-tolerant pools. Taints are optional.
  EOT
  type = map(object({
    machine_type       = optional(string, "n2-standard-4")
    disk_type          = optional(string, "pd-balanced")
    disk_size_gb       = optional(number, 100)
    min_nodes_per_zone = optional(number, 1)
    max_nodes_per_zone = optional(number, 3)
    spot               = optional(bool, false)
    labels             = optional(map(string), {})
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
    error_message = "At least one node pool is required."
  }

  validation {
    condition = alltrue([
      for k, _ in var.node_pools : can(regex("^[a-z][a-z0-9-]{0,37}[a-z0-9]$", k))
    ])
    error_message = "Node pool names must be 2-39 characters: lowercase letters, digits and hyphens, starting with a letter."
  }

  validation {
    condition = alltrue([
      for _, p in var.node_pools : p.min_nodes_per_zone >= 0 && p.max_nodes_per_zone >= 1 && p.min_nodes_per_zone <= p.max_nodes_per_zone
    ])
    error_message = "Each node pool needs 0 <= min_nodes_per_zone <= max_nodes_per_zone and max_nodes_per_zone >= 1."
  }

  validation {
    condition = alltrue([
      for _, p in var.node_pools : alltrue([for t in p.taints : contains(["NO_SCHEDULE", "PREFER_NO_SCHEDULE", "NO_EXECUTE"], t.effect)])
    ])
    error_message = "Taint effect must be NO_SCHEDULE, PREFER_NO_SCHEDULE or NO_EXECUTE."
  }
}

variable "secrets_encryption_key" {
  description = "Optional Cloud KMS key (projects/<p>/locations/<l>/keyRings/<r>/cryptoKeys/<k>) for application-layer encryption of Kubernetes Secrets. The module grants the GKE service agent encrypt/decrypt on it. Null leaves Secrets encrypted only with Google-managed keys."
  type        = string
  default     = null

  validation {
    condition     = var.secrets_encryption_key == null || can(regex("^projects/[^/]+/locations/[^/]+/keyRings/[^/]+/cryptoKeys/[^/]+$", var.secrets_encryption_key))
    error_message = "secrets_encryption_key must be a full Cloud KMS crypto key resource name."
  }
}

variable "upgrade_notification_topic" {
  description = "Optional Pub/Sub topic (projects/<p>/topics/<t>) that receives GKE upgrade and security notifications. Set this so the on-call team hears about upgrades."
  type        = string
  default     = null

  validation {
    condition     = var.upgrade_notification_topic == null || can(regex("^projects/[^/]+/topics/[^/]+$", var.upgrade_notification_topic))
    error_message = "upgrade_notification_topic must be a full Pub/Sub topic name: projects/<project>/topics/<topic>."
  }
}

variable "labels" {
  description = "Additional labels applied to the cluster. Keys and values must follow GCP label rules (lowercase)."
  type        = map(string)
  default     = {}
}
