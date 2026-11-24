# ---------------------------------------------------------------------------
# Cluster-specific inputs.
#
# These four are the only decisions the platform team makes per cluster.
# Everything else in this file has a production-shaped default chosen by the
# module; override only when a specific cluster genuinely needs it.
# ---------------------------------------------------------------------------

variable "project_id" {
  description = "Google Cloud project that owns both the cluster and the VPC (the network team's project)."
  type        = string
  nullable    = false
}

variable "name" {
  description = "Cluster name, e.g. \"prod-us-central1\"."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-z]([a-z0-9-]{0,38}[a-z0-9])?$", var.name))
    error_message = "name must be a valid GKE cluster name: lowercase letters, digits and dashes, starting with a letter, max 40 characters."
  }
}

variable "region" {
  description = "Google Cloud region, e.g. \"us-central1\". The module always creates a regional cluster: a multi-zone control plane and node pools spread across the region's zones."
  type        = string
  nullable    = false
}

variable "network" {
  description = "Name of the environment VPC created by the network team (\"apps-staging\" or \"apps-prod\")."
  type        = string
  nullable    = false
}

# ---------------------------------------------------------------------------
# Networking
# ---------------------------------------------------------------------------

variable "subnetwork" {
  description = "GKE subnetwork. Defaults to the network team's naming convention, \"<network>-gke-<region>\". The subnetwork must already exist and have secondary ranges named after pods_secondary_range_name and services_secondary_range_name."
  type        = string
  default     = null
}

variable "pods_secondary_range_name" {
  description = "Name of the subnetwork secondary range used for pod IPs (VPC-native routing)."
  type        = string
  default     = "pods"
}

variable "services_secondary_range_name" {
  description = "Name of the subnetwork secondary range used for Service IPs (VPC-native routing)."
  type        = string
  default     = "services"
}

variable "master_ipv4_cidr" {
  description = "RFC1918 /28 for the private control-plane endpoints. Must not overlap with anything the VPC is peered with."
  type        = string
  default     = "172.16.0.32/28"

  validation {
    condition     = can(cidrnetmask(var.master_ipv4_cidr)) && tonumber(split("/", var.master_ipv4_cidr)[1]) == 28
    error_message = "master_ipv4_cidr must be a valid /28 CIDR block."
  }
}

variable "enable_private_endpoint" {
  description = "If true, the control plane is only reachable from inside the VPC (kubectl then requires Cloud VPN/Interconnect or a bastion). The default keeps a public endpoint, fully authenticated and optionally restricted via master_authorized_networks."
  type        = bool
  default     = false
}

variable "master_authorized_networks" {
  description = "CIDRs allowed to reach the public control-plane endpoint (e.g. office or VPN ranges). Empty means reachable from any IP — still fully authenticated and encrypted."
  type = list(object({
    cidr_block   = string
    display_name = string
  }))
  default = []
}

# ---------------------------------------------------------------------------
# Release management
# ---------------------------------------------------------------------------

variable "release_channel" {
  description = "GKE release channel. REGULAR is the production default: new Kubernetes versions land after soak time and Google patches the fleet automatically."
  type        = string
  default     = "REGULAR"

  validation {
    condition     = contains(["RAPID", "REGULAR", "STABLE"], var.release_channel)
    error_message = "release_channel must be RAPID, REGULAR or STABLE."
  }
}

variable "kubernetes_version" {
  description = "Optional minimum control-plane version. Leave null (recommended) to track the release channel."
  type        = string
  default     = null
}

variable "maintenance_window" {
  description = "Recurring maintenance window (UTC). Control-plane and node upgrades only happen inside this window; the default is daily 02:00-06:00 UTC so security patches are never delayed long."
  type = object({
    start_time = string
    end_time   = string
    recurrence = string
  })
  default = {
    start_time = "2024-01-01T02:00:00Z"
    end_time   = "2024-01-01T06:00:00Z"
    recurrence = "FREQ=DAILY"
  }
}

variable "maintenance_exclusions" {
  description = "Time spans in which no maintenance happens at all (e.g. peak-season freeze). scope may be NO_UPGRADES, NO_MINOR_UPGRADES or NO_MINOR_OR_NODE_UPGRADES."
  type = list(object({
    name       = string
    start_time = string
    end_time   = string
    scope      = optional(string)
  }))
  default = []
}

# ---------------------------------------------------------------------------
# Node pools
# ---------------------------------------------------------------------------

variable "node_pools" {
  description = <<-EOT
    Map of node pools, keyed by pool name. For a regional cluster, min_count
    and max_count are PER ZONE. Defaults are production-shaped: pd-ssd boot
    disks, shielded nodes with secure boot, autoscaling, surge upgrades,
    auto-repair and auto-upgrade. Use labels + taints to dedicate pools to
    teams or workload classes; use spot pools for fault-tolerant batch work.
  EOT
  type = map(object({
    machine_type      = optional(string, "e2-standard-4")
    disk_size_gb      = optional(number, 100)
    disk_type         = optional(string, "pd-ssd")
    image_type        = optional(string, "COS_CONTAINERD")
    min_count         = optional(number, 1)
    max_count         = optional(number, 5)
    max_surge         = optional(number, 1)
    max_unavailable   = optional(number, 0)
    max_pods_per_node = optional(number)
    local_ssd_count   = optional(number, 0)
    spot              = optional(bool, false)
    auto_repair       = optional(bool, true)
    auto_upgrade      = optional(bool, true)
    node_locations    = optional(list(string))
    labels            = optional(map(string), {})
    resource_labels   = optional(map(string), {})
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
    condition     = alltrue([for name, pool in var.node_pools : pool.min_count >= 0 && pool.min_count <= pool.max_count])
    error_message = "Each node pool must satisfy 0 <= min_count <= max_count (per zone)."
  }

  validation {
    condition     = alltrue([for name, pool in var.node_pools : pool.max_surge > 0 || pool.max_unavailable > 0])
    error_message = "Each node pool needs max_surge or max_unavailable above zero, otherwise upgrades stall."
  }
}

# ---------------------------------------------------------------------------
# Security
# ---------------------------------------------------------------------------

variable "secrets_encryption_key" {
  description = "Optional Cloud KMS key (full resource ID) for application-layer secrets encryption. The GKE service agent (service-<project-number>@container-engine-robot.iam.gserviceaccount.com) must already have roles/cloudkms.cryptoKeyEncrypterDecrypter on the key."
  type        = string
  default     = null
}

variable "binary_authorization_evaluation_mode" {
  description = "Set to \"PROJECT_SINGLETON_POLICY_ENFORCE\" to enforce the project's Binary Authorization policy on deployments. Null (default) leaves Binary Authorization off."
  type        = string
  default     = null
}

variable "rbac_security_group" {
  description = "Optional Google Workspace group (e.g. \"gke-security-groups@example.com\") enabling Google Groups-based RBAC."
  type        = string
  default     = null
}

variable "enable_gcs_fuse_csi" {
  description = "Enable the Cloud Storage FUSE CSI driver so pods can mount buckets as filesystems. Uses Workload Identity, which this module always enables."
  type        = bool
  default     = false
}

# ---------------------------------------------------------------------------
# Observability
# ---------------------------------------------------------------------------

variable "logging_components" {
  description = "GKE logging components shipped to Cloud Logging."
  type        = list(string)
  default     = ["SYSTEM_COMPONENTS", "WORKLOADS"]
}

variable "monitoring_components" {
  description = "GKE monitoring components shipped to Cloud Monitoring."
  type        = list(string)
  default     = ["SYSTEM_COMPONENTS"]
}

variable "enable_managed_prometheus" {
  description = "Enable Google Cloud Managed Service for Prometheus collection on the cluster."
  type        = bool
  default     = true
}

variable "upgrade_notification_topic" {
  description = "Optional Pub/Sub topic (full resource ID, \"projects/.../topics/...\") that receives GKE upgrade notifications."
  type        = string
  default     = null
}

# ---------------------------------------------------------------------------
# Workload identity: how product teams reach Pub/Sub, Cloud Storage,
# Cloud SQL, ... without exported keys.
# ---------------------------------------------------------------------------

variable "workload_service_accounts" {
  description = <<-EOT
    Google service accounts created for product-team workloads. Each entry
    creates a GSA, grants it project_roles, and binds it to a Kubernetes
    service account via Workload Identity so pods authenticate to Google APIs
    without keys. The map key is the GSA account id (6-30 chars, lowercase);
    the bound Kubernetes service account defaults to the same name.
  EOT
  type = map(object({
    display_name  = optional(string)
    project_roles = optional(list(string), [])
    namespace     = string
    ksa_name      = optional(string)
  }))
  default = {}
}

# ---------------------------------------------------------------------------
# Misc
# ---------------------------------------------------------------------------

variable "labels" {
  description = "GCP labels applied to the cluster and to every node (as GCE resource labels)."
  type        = map(string)
  default     = {}
}

variable "deletion_protection" {
  description = "Prevent accidental cluster deletion. Must be set to false (in a separate apply) before the cluster can be destroyed."
  type        = bool
  default     = true
}
