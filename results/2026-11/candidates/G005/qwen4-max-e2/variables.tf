# ---------------------------------------------------------------------------
# Required: the things that are specific to each cluster. Everything else has
# a production-safe default owned by this module.
# ---------------------------------------------------------------------------

variable "project_id" {
  description = "Project that hosts the cluster. Must be the same project that owns the apps-<environment> VPC."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "project_id must be a valid Google Cloud project ID."
  }
}

variable "environment" {
  description = "Environment the cluster belongs to. Selects the network team's VPC: apps-staging or apps-prod."
  type        = string

  validation {
    condition     = contains(["staging", "prod"], var.environment)
    error_message = "environment must be \"staging\" or \"prod\" (the network team owns one VPC per environment)."
  }
}

variable "region" {
  description = "US region to deploy the regional cluster into. The subnet apps-<environment>-gke-<region> must already exist there."
  type        = string

  validation {
    condition     = can(regex("^us-[a-z]+[0-9]$", var.region))
    error_message = "region must be a US region (e.g. us-central1, us-east1, us-west1)."
  }
}

variable "cluster_name" {
  description = "Name of the GKE cluster. Must be unique within the project/region."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,38}[a-z0-9]$", var.cluster_name))
    error_message = "cluster_name must be 2-40 chars, lowercase letters/digits/hyphens, start with a letter and end with a letter or digit."
  }
}

# ---------------------------------------------------------------------------
# Optional: sizing and behaviour. Defaults are production-safe; override only
# when a cluster genuinely needs something different.
# ---------------------------------------------------------------------------

variable "release_channel" {
  description = "GKE release channel. REGULAR is the production default: new Kubernetes versions after they are proven, with automatic patching."
  type        = string
  default     = "REGULAR"

  validation {
    condition     = contains(["RAPID", "REGULAR", "STABLE"], var.release_channel)
    error_message = "release_channel must be RAPID, REGULAR or STABLE. Unenrolled clusters are not allowed by this module."
  }
}

variable "node_locations" {
  description = "Zones within the region for nodes. null (default) lets GKE spread nodes across three zones, which is what production clusters should do."
  type        = list(string)
  default     = null
}

variable "machine_type" {
  description = "Machine type for the primary (general purpose) node pool."
  type        = string
  default     = "e2-standard-4"
}

variable "disk_type" {
  description = "Boot disk type for the primary node pool."
  type        = string
  default     = "pd-balanced"
}

variable "disk_size_gb" {
  description = "Boot disk size (GB) for the primary node pool. 100 GB leaves headroom for images and ephemeral storage on shared nodes."
  type        = number
  default     = 100

  validation {
    condition     = var.disk_size_gb >= 50
    error_message = "disk_size_gb must be at least 50 GB for production nodes."
  }
}

variable "min_node_count" {
  description = "Autoscaler minimum nodes PER ZONE for the primary pool. With the default three zones, 1 means the pool never drops below three nodes."
  type        = number
  default     = 1

  validation {
    condition     = var.min_node_count >= 1
    error_message = "min_node_count must be at least 1 per zone so the cluster survives a zone failure."
  }
}

variable "max_node_count" {
  description = "Autoscaler maximum nodes PER ZONE for the primary pool."
  type        = number
  default     = 3

  validation {
    condition     = var.max_node_count >= 1
    error_message = "max_node_count must be at least 1."
  }
}

variable "additional_node_pools" {
  description = <<-EOT
    Extra node pools keyed by pool name, for teams that need dedicated capacity
    (e.g. memory-heavy workloads or GPU-less batch). They get the same
    hardening as the primary pool. Use taints to keep general workloads off.
  EOT
  type = map(object({
    machine_type   = optional(string, "e2-standard-4")
    disk_type      = optional(string, "pd-balanced")
    disk_size_gb   = optional(number, 100)
    min_node_count = optional(number, 1)
    max_node_count = optional(number, 3)
    spot           = optional(bool, false)
    labels         = optional(map(string), {})
    taints = optional(list(object({
      key    = string
      value  = string
      effect = string # NO_SCHEDULE | PREFER_NO_SCHEDULE | NO_EXECUTE
    })), [])
  }))
  default = {}

  validation {
    condition = alltrue([
      for name, pool in var.additional_node_pools :
      can(regex("^[a-z][a-z0-9-]{0,38}[a-z0-9]$", name)) && name != "primary"
    ])
    error_message = "Additional pool names must be valid GKE node pool names and must not be \"primary\" (reserved for the module-managed pool)."
  }

  validation {
    condition = alltrue([
      for _, pool in var.additional_node_pools :
      alltrue([for t in pool.taints : contains(["NO_SCHEDULE", "PREFER_NO_SCHEDULE", "NO_EXECUTE"], t.effect)])
    ])
    error_message = "Taint effects must be NO_SCHEDULE, PREFER_NO_SCHEDULE or NO_EXECUTE."
  }
}

variable "enable_private_endpoint" {
  description = <<-EOT
    When true (default) the control plane has no public IP and is reachable
    only from inside the VPC (and networks peered/connected to it, thanks to
    master global access). Set false only for clusters that must be
    administered from outside the VPC, and then always supply
    master_authorized_networks.
  EOT
  type        = bool
  default     = true
}

variable "master_authorized_networks" {
  description = "CIDRs allowed to reach the control plane endpoint. Empty by default: with the private endpoint, only the VPC can reach it. Required in practice if enable_private_endpoint is false."
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

variable "master_ipv4_cidr_block" {
  description = "A free /28 range for the private control plane endpoint. Must not overlap anything in the VPC; coordinate with the network team if the default is taken."
  type        = string
  default     = "172.16.0.0/28"

  validation {
    condition     = can(cidrhost(var.master_ipv4_cidr_block, 0)) && tonumber(split("/", var.master_ipv4_cidr_block)[1]) == 28
    error_message = "master_ipv4_cidr_block must be a /28 CIDR."
  }
}

variable "database_encryption_key_name" {
  description = "Optional Cloud KMS key (projects/.../keyRings/.../cryptoKeys/...) to encrypt Kubernetes Secrets at the application layer (etcd). Key must be in the same region as the cluster."
  type        = string
  default     = null
}

variable "binary_authorization_mode" {
  description = "Binary Authorization evaluation mode. DISABLED by default so clusters work before a project policy exists; move to PROJECT_SINGLE_POLICY_EVALUATION, then ENFORCED, as the supply-chain policy rolls out."
  type        = string
  default     = "DISABLED"

  validation {
    condition     = contains(["DISABLED", "PROJECT_SINGLE_POLICY_EVALUATION", "PROJECT_SINGLE_POLICY_ENFORCED"], var.binary_authorization_mode)
    error_message = "binary_authorization_mode must be DISABLED, PROJECT_SINGLE_POLICY_EVALUATION or PROJECT_SINGLE_POLICY_ENFORCED."
  }
}

variable "deletion_protection" {
  description = "Protect the cluster from accidental tofu destroy. Set true for long-lived production clusters; false keeps ephemeral/CI clusters easy to tear down."
  type        = bool
  default     = false
}

variable "labels" {
  description = "Extra resource labels applied to the cluster and nodes (e.g. team, cost-center). The module always adds environment and managed-by."
  type        = map(string)
  default     = {}
}
