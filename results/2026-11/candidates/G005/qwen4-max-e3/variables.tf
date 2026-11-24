# ---------------------------------------------------------------------------
# Required: what is specific to each cluster
# ---------------------------------------------------------------------------

variable "project_id" {
  description = "Project that hosts the cluster. Must be the same project that owns the environment VPC (apps-staging / apps-prod)."
  type        = string
}

variable "environment" {
  description = "Environment name. Selects the VPC owned by the network team: apps-<environment>."
  type        = string

  validation {
    condition     = contains(["staging", "prod"], var.environment)
    error_message = "environment must be \"staging\" or \"prod\"."
  }
}

variable "region" {
  description = "US region to deploy the (regional, multi-zonal) cluster into, e.g. us-central1. The network team's subnet <vpc>-gke-<region> must exist there."
  type        = string

  validation {
    condition     = can(regex("^us-[a-z]+[0-9]$", var.region))
    error_message = "region must be a US region such as us-central1, us-east1 or us-west1."
  }
}

variable "cluster_name" {
  description = "Name of the GKE cluster. Lowercase letters, digits and hyphens; 2-20 characters (bounded so derived service-account IDs stay valid)."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,18}[a-z0-9]$", var.cluster_name))
    error_message = "cluster_name must be 2-20 characters, start with a letter, end with a letter or digit, and contain only lowercase letters, digits and hyphens."
  }
}

variable "master_authorized_networks" {
  description = "CIDR ranges allowed to reach the Kubernetes control-plane endpoint (e.g. office/VPN/bastion ranges). Required: the endpoint is never left open to the whole internet. Ignored for reachability purposes when enable_private_endpoint = true, but still recorded."
  type = list(object({
    cidr_block   = string
    display_name = optional(string, "authorized")
  }))

  validation {
    condition     = length(var.master_authorized_networks) > 0
    error_message = "Provide at least one authorized network so control-plane access is explicitly restricted."
  }

  validation {
    condition     = alltrue([for n in var.master_authorized_networks : can(cidrnetmask(n.cidr_block))])
    error_message = "Every master_authorized_networks entry must have a valid cidr_block."
  }
}

# ---------------------------------------------------------------------------
# Networking knobs (sensible production defaults)
# ---------------------------------------------------------------------------

variable "master_ipv4_cidr_block" {
  description = "/28 RFC1918 range for the private control-plane endpoint. Must not overlap the VPC's subnets or pod/service ranges. Override per cluster if the default collides."
  type        = string
  default     = "172.16.0.0/28"

  validation {
    condition     = can(cidrnetmask(var.master_ipv4_cidr_block)) && endswith(var.master_ipv4_cidr_block, "/28")
    error_message = "master_ipv4_cidr_block must be a valid /28 CIDR."
  }
}

variable "enable_private_endpoint" {
  description = "If true, the control plane has no public IP at all; kubectl must run from inside the VPC (VPN/interconnect/bastion). If false (default), the public endpoint exists but only master_authorized_networks can reach it."
  type        = bool
  default     = false
}

variable "node_locations" {
  description = "Zones within the region for nodes. null (default) spreads nodes across all zones in the region for maximum resilience."
  type        = list(string)
  default     = null
}

# ---------------------------------------------------------------------------
# Cluster lifecycle / operations
# ---------------------------------------------------------------------------

variable "release_channel" {
  description = "GKE release channel. REGULAR (default) is the recommended production balance; STABLE is the most conservative."
  type        = string
  default     = "REGULAR"

  validation {
    condition     = contains(["RAPID", "REGULAR", "STABLE"], var.release_channel)
    error_message = "release_channel must be RAPID, REGULAR or STABLE."
  }
}

variable "min_master_version" {
  description = "Optional floor for the control-plane version. Leave null to let the release channel manage versions."
  type        = string
  default     = null
}

variable "maintenance_start_time" {
  description = "Daily maintenance window start time (UTC, HH:MM). GKE picks a 4-hour window from this point; choose an off-peak hour."
  type        = string
  default     = "03:00"

  validation {
    condition     = can(regex("^([01][0-9]|2[0-3]):00$", var.maintenance_start_time))
    error_message = "maintenance_start_time must be an hour in HH:00 format (UTC)."
  }
}

variable "maintenance_exclusions" {
  description = "Named freeze windows (RFC3339 timestamps) during which minor-version upgrades are blocked, e.g. a launch or holiday freeze. Patch upgrades still apply."
  type = map(object({
    start_time = string
    end_time   = string
  }))
  default = {}
}

variable "deletion_protection" {
  description = "Protect the cluster from accidental `tofu destroy`. Keep true for real production clusters; set false only for disposable/test instantiations."
  type        = bool
  default     = true
}

variable "resource_labels" {
  description = "Extra GCP resource labels applied to the cluster (merged with module-managed labels)."
  type        = map(string)
  default     = {}
}

# ---------------------------------------------------------------------------
# Node pools
# ---------------------------------------------------------------------------

variable "primary_node_pool" {
  description = "Sizing of the general-purpose node pool. Defaults are production-safe: autoscaled 1-3 nodes per zone on balanced persistent disks."
  type = object({
    machine_type   = optional(string, "e2-standard-4")
    min_node_count = optional(number, 1)
    max_node_count = optional(number, 3)
    disk_size_gb   = optional(number, 100)
    disk_type      = optional(string, "pd-balanced")
  })
  default = {}

  validation {
    condition     = var.primary_node_pool.min_node_count >= 1 && var.primary_node_pool.max_node_count >= var.primary_node_pool.min_node_count
    error_message = "primary_node_pool needs min_node_count >= 1 and max_node_count >= min_node_count (counts are per zone)."
  }
}

variable "extra_node_pools" {
  description = "Additional node pools keyed by name, for workloads that need dedicated hardware, taints or spot capacity. Same secure node defaults as the primary pool."
  type = map(object({
    machine_type   = optional(string, "e2-standard-4")
    min_node_count = optional(number, 1)
    max_node_count = optional(number, 3)
    disk_size_gb   = optional(number, 100)
    disk_type      = optional(string, "pd-balanced")
    spot           = optional(bool, false)
    labels         = optional(map(string), {})
    taints = optional(list(object({
      key    = string
      value  = string
      effect = string
    })), [])
  }))
  default = {}
}

# ---------------------------------------------------------------------------
# Workload Identity for product-team workloads (Pub/Sub, GCS, Cloud SQL, ...)
# ---------------------------------------------------------------------------

variable "workload_identities" {
  description = <<-EOT
    Per-workload Google service accounts wired to Kubernetes service accounts via
    Workload Identity (no exported keys). Key = short name for the identity.
    Each entry creates a GSA, grants it the listed project-level IAM roles
    (e.g. roles/pubsub.subscriber, roles/storage.objectViewer, roles/cloudsql.client),
    and allows the KSA <namespace>/<ksa_name> to impersonate it.
  EOT
  type = map(object({
    namespace = string
    ksa_name  = optional(string, "default")
    roles     = optional(list(string), [])
  }))
  default = {}

  validation {
    condition     = alltrue([for k in keys(var.workload_identities) : can(regex("^[a-z]([a-z0-9-]{0,25}[a-z0-9])?$", k))])
    error_message = "workload_identities keys must be 1-27 chars of lowercase letters/digits/hyphens, starting with a letter and ending alphanumeric."
  }
}

# ---------------------------------------------------------------------------
# Optional hardening / DR features
# ---------------------------------------------------------------------------

variable "binary_authorization_evaluation_mode" {
  description = "Binary Authorization enforcement. DISABLED by default; set PROJECT_SINGLETON_POLICY_ENFORCE once the project has an admission policy."
  type        = string
  default     = "DISABLED"

  validation {
    condition     = contains(["DISABLED", "PROJECT_SINGLETON_POLICY_ENFORCE"], var.binary_authorization_evaluation_mode)
    error_message = "binary_authorization_evaluation_mode must be DISABLED or PROJECT_SINGLETON_POLICY_ENFORCE."
  }
}

variable "database_encryption" {
  description = "Optional CMEK encryption of cluster secrets at rest (application-layer secrets encryption). key_name is a Cloud KMS crypto key in the same region."
  type = object({
    key_name = string
    state    = optional(string, "ENCRYPTED")
  })
  default = null
}

variable "enable_managed_prometheus" {
  description = "Enable Google Managed Service for Prometheus collection alongside Cloud Monitoring."
  type        = bool
  default     = true
}

variable "enable_intranode_visibility" {
  description = "Enable intra-node VPC flow visibility (useful for auditing pod-to-pod traffic on the same node)."
  type        = bool
  default     = true
}

variable "enable_backup" {
  description = "Create a GKE Backup for GKE plan (daily, all namespaces) for disaster recovery. Requires the GKE Backup API on the project."
  type        = bool
  default     = false
}

variable "backup_retain_days" {
  description = "How long daily backups are retained when enable_backup = true."
  type        = number
  default     = 14
}
