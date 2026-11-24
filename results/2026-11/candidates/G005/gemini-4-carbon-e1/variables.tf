# -----------------------------------------------------------------------------
# Required cluster-specific inputs
# -----------------------------------------------------------------------------

variable "project_id" {
  description = "Google Cloud project ID hosting the shared environment VPCs and this GKE cluster."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "project_id must be a valid Google Cloud project ID (6-30 lowercase letters, digits, or hyphens, starting with a letter)."
  }
}

variable "name" {
  description = "Name of the GKE cluster (must be unique within the project and region)."
  type        = string

  validation {
    condition     = can(regex("^[a-z]([a-z0-9-]{0,38}[a-z0-9])?$", var.name))
    error_message = "name must be 1-40 characters of lowercase letters, numbers, and hyphens, starting with a letter and not ending with a hyphen."
  }
}

variable "environment" {
  description = "Target environment for the cluster ('staging' or 'prod'). Determines the shared VPC (apps-<environment>) and regional subnet (apps-<environment>-gke-<region>)."
  type        = string

  validation {
    condition     = contains(["staging", "prod"], var.environment)
    error_message = "environment must be either 'staging' or 'prod' (corresponding to VPCs 'apps-staging' and 'apps-prod')."
  }
}

variable "region" {
  description = "US Google Cloud region for the regional GKE cluster and subnet (e.g., 'us-central1', 'us-east4', 'us-west1')."
  type        = string

  validation {
    condition     = can(regex("^us-[a-z]+[0-9]$", var.region))
    error_message = "region must be a valid US Google Cloud region (for example, 'us-central1', 'us-east1', 'us-east4', or 'us-west1')."
  }
}

# -----------------------------------------------------------------------------
# Networking & Control Plane Access
# -----------------------------------------------------------------------------

variable "node_locations" {
  description = "Optional explicit list of zones within var.region in which to run worker nodes (e.g., ['us-central1-a', 'us-central1-b', 'us-central1-c']). When empty, GKE uses default zones across the region."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for z in var.node_locations : can(regex("^us-[a-z]+[0-9]-[a-z]$", z))])
    error_message = "Each entry in node_locations must be a valid US zone name (e.g., 'us-central1-a')."
  }
}

variable "pods_secondary_range_name" {
  description = "Name of the subnet secondary IP range used for Pod IPs."
  type        = string
  default     = "pods"
}

variable "services_secondary_range_name" {
  description = "Name of the subnet secondary IP range used for Kubernetes Service ClusterIPs."
  type        = string
  default     = "services"
}

variable "enable_private_endpoint" {
  description = "When true, disables public IP access to the Kubernetes API server so control plane traffic is only reachable from private networks (VPC, Cloud VPN, Cloud Interconnect)."
  type        = bool
  default     = false
}

variable "master_ipv4_cidr_block" {
  description = "Optional RFC1918 /28 CIDR block for VPC-peered private control plane networking. Leave null (default) to use GKE Private Service Connect without consuming /28 peering ranges."
  type        = string
  default     = null

  validation {
    condition     = var.master_ipv4_cidr_block == null || can(cidrnetmask(var.master_ipv4_cidr_block)) && can(regex("/28$", var.master_ipv4_cidr_block))
    error_message = "master_ipv4_cidr_block must be null or a valid IPv4 /28 CIDR block (e.g., '172.16.0.0/28')."
  }
}

variable "authorized_networks" {
  description = "List of CIDR blocks permitted to reach the Kubernetes API server endpoint (e.g., corporate VPN egress, CI/CD runners, or bastion subnets)."
  type = list(object({
    cidr_block   = string
    display_name = string
  }))
  default = []

  validation {
    condition     = alltrue([for n in var.authorized_networks : can(cidrhost(n.cidr_block, 0))])
    error_message = "Every entry in authorized_networks must have a valid IPv4 CIDR in cidr_block."
  }
}

variable "enable_gateway_api" {
  description = "Whether to enable the Kubernetes Gateway API (CHANNEL_STANDARD) for multi-team ingress and traffic routing."
  type        = bool
  default     = true
}

variable "enable_cilium_clusterwide_network_policy" {
  description = "Enable CiliumClusterwideNetworkPolicy CRDs on Dataplane V2 so the platform team can enforce cluster-wide baseline network isolation across all product team namespaces."
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# Kubernetes Release Lifecycle & Maintenance
# -----------------------------------------------------------------------------

variable "release_channel" {
  description = "GKE release channel governing automatic Kubernetes version upgrades and security patches."
  type        = string
  default     = "REGULAR"

  validation {
    condition     = contains(["RAPID", "REGULAR", "STABLE"], var.release_channel)
    error_message = "release_channel must be one of 'RAPID', 'REGULAR', or 'STABLE'."
  }
}

variable "min_master_version" {
  description = "Optional minimum Kubernetes version for initial cluster creation (for example, '1.31'). Managed upgrades follow var.release_channel thereafter."
  type        = string
  default     = null
}

variable "maintenance_recurring_window" {
  description = "Recurring off-peak maintenance window for GKE control plane and node upgrades (RFC3339 timestamps and RFC5545 RRULE). Defaults to weekends 03:00-11:00 UTC (late night US hours, providing >= 48h per 32 days)."
  type = object({
    start_time = string
    end_time   = string
    recurrence = string
  })
  default = {
    start_time = "2025-01-04T03:00:00Z"
    end_time   = "2025-01-04T11:00:00Z"
    recurrence = "FREQ=WEEKLY;BYDAY=SA,SU"
  }
}

variable "maintenance_exclusions" {
  description = "Optional maintenance exclusion windows (e.g., peak business events or change freezes)."
  type = list(object({
    name       = string
    start_time = string
    end_time   = string
    scope      = optional(string, "NO_UPGRADES")
  }))
  default = []

  validation {
    condition = alltrue([
      for ex in var.maintenance_exclusions :
      contains(["NO_UPGRADES", "NO_MINOR_UPGRADES", "NO_MINOR_OR_NODE_UPGRADES"], ex.scope)
    ])
    error_message = "Each maintenance exclusion scope must be 'NO_UPGRADES', 'NO_MINOR_UPGRADES', or 'NO_MINOR_OR_NODE_UPGRADES'."
  }
}

# -----------------------------------------------------------------------------
# Node Pools (GKE Standard)
# -----------------------------------------------------------------------------

variable "system_node_pool" {
  description = <<-EOT
    Configuration for the dedicated system node pool hosting critical GKE add-ons
    (CoreDNS/kube-dns, Metrics Server, Konnectivity, GKE Metadata Server, Dataplane V2).
    Tainted with components.gke.io/gke-managed-components=true:NoSchedule so product
    team workloads cannot starve cluster system components.
  EOT
  type = object({
    enabled            = optional(bool, true)
    machine_type       = optional(string, "e2-standard-2")
    min_nodes_per_zone = optional(number, 1)
    max_nodes_per_zone = optional(number, 3)
    disk_size_gb       = optional(number, 50)
    disk_type          = optional(string, "pd-balanced")
    max_surge          = optional(number, 1)
    max_unavailable    = optional(number, 0)
    labels             = optional(map(string), {})
    network_tags       = optional(list(string), [])
  })
  default = {}

  validation {
    condition = (
      var.system_node_pool.min_nodes_per_zone >= 1 &&
      var.system_node_pool.max_nodes_per_zone >= var.system_node_pool.min_nodes_per_zone &&
      var.system_node_pool.disk_size_gb >= 30 &&
      (var.system_node_pool.max_surge + var.system_node_pool.max_unavailable) >= 1
    )
    error_message = "system_node_pool requires min_nodes_per_zone >= 1, max_nodes_per_zone >= min_nodes_per_zone, disk_size_gb >= 30, and (max_surge + max_unavailable) >= 1."
  }
}

variable "node_pools" {
  description = <<-EOT
    Map of workload node pools for product team deployments. Defaults to a resilient
    multi-zone 'general' pool; override or extend per cluster for specialized sizing,
    team isolation (labels + taints), or Spot batch capacity.
  EOT
  type = map(object({
    machine_type       = optional(string, "e2-standard-4")
    min_nodes_per_zone = optional(number, 1)
    max_nodes_per_zone = optional(number, 10)
    disk_size_gb       = optional(number, 100)
    disk_type          = optional(string, "pd-balanced")
    spot               = optional(bool, false)
    max_surge          = optional(number, 1)
    max_unavailable    = optional(number, 0)
    labels             = optional(map(string), {})
    network_tags       = optional(list(string), [])
    taints = optional(list(object({
      key    = string
      value  = string
      effect = string
    })), [])
  }))
  default = {
    general = {
      machine_type       = "e2-standard-4"
      min_nodes_per_zone = 1
      max_nodes_per_zone = 10
      disk_size_gb       = 100
      disk_type          = "pd-balanced"
      labels = {
        "workload-tier" = "general"
      }
    }
  }

  validation {
    condition = alltrue([
      for k, np in var.node_pools :
      k != "system" &&
      can(regex("^[a-z]([a-z0-9-]{0,38}[a-z0-9])?$", k)) &&
      np.min_nodes_per_zone >= 0 &&
      np.max_nodes_per_zone >= np.min_nodes_per_zone &&
      np.max_nodes_per_zone >= 1 &&
      np.disk_size_gb >= 30 &&
      (np.max_surge + np.max_unavailable) >= 1 &&
      alltrue([
        for t in np.taints :
        contains(["NO_SCHEDULE", "PREFER_NO_SCHEDULE", "NO_EXECUTE"], t.effect)
      ])
    ])
    error_message = "Each workload node_pools entry must have a valid name (not 'system'), 0 <= min_nodes_per_zone <= max_nodes_per_zone (max >= 1), disk_size_gb >= 30, (max_surge + max_unavailable) >= 1, and taint effects in ['NO_SCHEDULE', 'PREFER_NO_SCHEDULE', 'NO_EXECUTE']."
  }
}

# -----------------------------------------------------------------------------
# Workload Identity & Google Cloud Service Access (Pub/Sub, GCS, Cloud SQL)
# -----------------------------------------------------------------------------

variable "workload_identities" {
  description = <<-EOT
    Optional map of Workload Identity bindings allowing Kubernetes ServiceAccounts to
    authenticate to Google Cloud services (such as Pub/Sub, Cloud Storage, and Cloud SQL)
    without static keys. Creates a dedicated Google Service Account when existing_gsa_email
    is omitted, grants any specified project-level IAM roles, and binds
    roles/iam.workloadIdentityUser to namespace/ksa_name.
  EOT
  type = map(object({
    namespace          = string
    ksa_name           = string
    description        = optional(string, "Managed by OpenTofu for GKE Workload Identity")
    project_roles      = optional(list(string), [])
    existing_gsa_email = optional(string, null)
  }))
  default = {}

  validation {
    condition = alltrue([
      for k, wi in var.workload_identities :
      can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", k)) &&
      length(wi.namespace) > 0 &&
      length(wi.ksa_name) > 0
    ])
    error_message = "Each workload_identities entry must use a lowercase alphanumeric/hyphen key and specify non-empty namespace and ksa_name."
  }
}

variable "enable_gcs_fuse_csi_driver" {
  description = "Enable the Cloud Storage FUSE CSI driver so pods can mount Cloud Storage buckets as volumes via Workload Identity."
  type        = bool
  default     = true
}

variable "enable_secret_manager_addon" {
  description = "Enable the Secret Manager add-on CSI provider so workloads can mount secrets from Google Cloud Secret Manager."
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# Security, Encryption, Governance & Observability
# -----------------------------------------------------------------------------

variable "deletion_protection" {
  description = "Whether to enable GKE cluster deletion protection against accidental destruction."
  type        = bool
  default     = true
}

variable "database_encryption_key_name" {
  description = "Optional Cloud KMS CryptoKey resource ID (projects/.../locations/.../keyRings/.../cryptoKeys/...) for application-layer encryption of Kubernetes Secrets in etcd."
  type        = string
  default     = null
}

variable "boot_disk_kms_key" {
  description = "Optional regional Cloud KMS CryptoKey resource ID for customer-managed encryption of node persistent boot disks."
  type        = string
  default     = null
}

variable "authenticator_security_group" {
  description = "Optional Google Groups for RBAC security group email (e.g., 'gke-security-groups@example.com') to support group-based Kubernetes RBAC across product teams."
  type        = string
  default     = null
}

variable "binary_authorization_evaluation_mode" {
  description = "Binary Authorization evaluation mode ('DISABLED' or 'PROJECT_SINGLETON_POLICY_ENFORCE')."
  type        = string
  default     = "DISABLED"

  validation {
    condition     = contains(["DISABLED", "PROJECT_SINGLETON_POLICY_ENFORCE"], var.binary_authorization_evaluation_mode)
    error_message = "binary_authorization_evaluation_mode must be 'DISABLED' or 'PROJECT_SINGLETON_POLICY_ENFORCE'."
  }
}

variable "security_posture_mode" {
  description = "GKE Security Posture configuration auditing mode ('BASIC', 'ENTERPRISE', or 'DISABLED')."
  type        = string
  default     = "BASIC"

  validation {
    condition     = contains(["BASIC", "ENTERPRISE", "DISABLED"], var.security_posture_mode)
    error_message = "security_posture_mode must be 'BASIC', 'ENTERPRISE', or 'DISABLED'."
  }
}

variable "security_posture_vulnerability_mode" {
  description = "GKE container workload vulnerability scanning mode ('VULNERABILITY_BASIC', 'VULNERABILITY_ENTERPRISE', or 'VULNERABILITY_DISABLED')."
  type        = string
  default     = "VULNERABILITY_BASIC"

  validation {
    condition     = contains(["VULNERABILITY_BASIC", "VULNERABILITY_ENTERPRISE", "VULNERABILITY_DISABLED"], var.security_posture_vulnerability_mode)
    error_message = "security_posture_vulnerability_mode must be 'VULNERABILITY_BASIC', 'VULNERABILITY_ENTERPRISE', or 'VULNERABILITY_DISABLED'."
  }
}

variable "enable_cost_allocation" {
  description = "Enable GKE Cost Allocation for per-namespace and per-team label cost breakdown in Cloud Billing exports."
  type        = bool
  default     = true
}

variable "enable_managed_prometheus" {
  description = "Enable Google Cloud Managed Service for Prometheus for cluster and product workload metrics."
  type        = bool
  default     = true
}

variable "enable_dataplane_v2_observability" {
  description = "Enable Dataplane V2 packet/flow metrics and Hubble relay for network policy troubleshooting across product teams."
  type        = bool
  default     = true
}

variable "enable_vertical_pod_autoscaling" {
  description = "Enable Vertical Pod Autoscaling (VPA) controller on the cluster."
  type        = bool
  default     = true
}

variable "logging_components" {
  description = "GKE components exporting logs to Cloud Logging."
  type        = list(string)
  default = [
    "SYSTEM_COMPONENTS",
    "WORKLOADS",
    "APISERVER",
    "CONTROLLER_MANAGER",
    "SCHEDULER",
  ]

  validation {
    condition = alltrue([
      for c in var.logging_components :
      contains(["SYSTEM_COMPONENTS", "WORKLOADS", "APISERVER", "CONTROLLER_MANAGER", "SCHEDULER"], c)
    ])
    error_message = "logging_components may only contain 'SYSTEM_COMPONENTS', 'WORKLOADS', 'APISERVER', 'CONTROLLER_MANAGER', or 'SCHEDULER'."
  }
}

variable "monitoring_components" {
  description = "GKE components exporting metrics to Cloud Monitoring."
  type        = list(string)
  default = [
    "SYSTEM_COMPONENTS",
    "APISERVER",
    "SCHEDULER",
    "CONTROLLER_MANAGER",
    "STORAGE",
    "HPA",
    "POD",
    "DAEMONSET",
    "DEPLOYMENT",
    "STATEFULSET",
    "CADVISOR",
    "KUBELET",
  ]
}

variable "notification_pubsub_topic" {
  description = "Optional Pub/Sub topic ID ('projects/<project>/topics/<topic>') to receive GKE upgrade and security bulletin notifications."
  type        = string
  default     = null
}

variable "labels" {
  description = "Additional Google Cloud resource labels applied to the cluster and node pools."
  type        = map(string)
  default     = {}

  validation {
    condition = alltrue([
      for k, v in var.labels :
      can(regex("^[a-z][a-z0-9_-]{0,62}$", k)) && can(regex("^[a-z0-9_-]{0,63}$", v))
    ])
    error_message = "Label keys must start with a lowercase letter (max 63 chars) and values may contain only lowercase letters, digits, underscores, and hyphens (max 63 chars)."
  }
}
