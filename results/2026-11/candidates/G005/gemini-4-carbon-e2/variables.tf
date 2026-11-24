# -----------------------------------------------------------------------------
# Required Cluster Identity & Placement Inputs
# -----------------------------------------------------------------------------

variable "project_id" {
  description = "Google Cloud project ID hosting the environment VPC and GKE cluster."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "project_id must be a valid Google Cloud project ID (6-30 lowercase letters, digits, or hyphens)."
  }
}

variable "cluster_name" {
  description = "Unique name of the GKE Standard cluster."
  type        = string

  validation {
    condition     = can(regex("^[a-z]([a-z0-9-]{0,38}[a-z0-9])?$", var.cluster_name))
    error_message = "cluster_name must be 1-40 characters, start with a lowercase letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "environment" {
  description = "Target environment ('staging' or 'prod'). Selects the network team's VPC (apps-<environment>) and subnet (apps-<environment>-gke-<region>)."
  type        = string

  validation {
    condition     = contains(["staging", "prod"], var.environment)
    error_message = "environment must be either 'staging' or 'prod'."
  }
}

variable "region" {
  description = "US Google Cloud region for the regional GKE control plane and regional subnet (for example, 'us-central1' or 'us-east4')."
  type        = string

  validation {
    condition     = can(regex("^us-[a-z]+[0-9]+$", var.region))
    error_message = "region must be a valid US Google Cloud region such as 'us-central1', 'us-east1', 'us-east4', or 'us-west1'."
  }
}

# -----------------------------------------------------------------------------
# General Cluster Metadata & Lifecycle
# -----------------------------------------------------------------------------

variable "description" {
  description = "Optional human-readable description for the GKE cluster."
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
    error_message = "Label keys and values must contain only lowercase letters, numbers, underscores, and hyphens (keys must start with a lowercase letter)."
  }
}

variable "deletion_protection" {
  description = "Prevent accidental cluster deletion via OpenTofu/API. Disable explicitly before intentionally retiring a cluster."
  type        = bool
  default     = true
}

variable "release_channel" {
  description = "GKE release channel managing control plane and node version lifecycles ('REGULAR', 'STABLE', or 'RAPID')."
  type        = string
  default     = "REGULAR"

  validation {
    condition     = contains(["RAPID", "REGULAR", "STABLE"], var.release_channel)
    error_message = "release_channel must be one of 'RAPID', 'REGULAR', or 'STABLE'."
  }
}

variable "node_locations" {
  description = "Optional list of specific compute zones within the region for worker nodes. Defaults to GKE's automatic 3-zone regional placement."
  type        = list(string)
  default     = null

  validation {
    condition = var.node_locations == null || (
      length(var.node_locations) >= 2 &&
      alltrue([for z in var.node_locations : can(regex("^us-[a-z]+[0-9]+-[a-z]$", z))])
    )
    error_message = "When set, node_locations must specify at least 2 valid US compute zones for high availability."
  }
}

# -----------------------------------------------------------------------------
# Networking & Control Plane Access
# -----------------------------------------------------------------------------

variable "vpc_name_override" {
  description = "Optional override for the VPC name. Defaults to 'apps-<environment>'."
  type        = string
  default     = null
}

variable "subnet_name_override" {
  description = "Optional override for the regional GKE subnet name. Defaults to '<vpc>-gke-<region>'."
  type        = string
  default     = null
}

variable "pods_secondary_range_name" {
  description = "Name of the subnet secondary IP range used for GKE Pod IPs."
  type        = string
  default     = "pods"
}

variable "services_secondary_range_name" {
  description = "Name of the subnet secondary IP range used for Kubernetes Service ClusterIPs."
  type        = string
  default     = "services"
}

variable "default_max_pods_per_node" {
  description = "Default maximum number of Pods per node (controls per-node alias IP range size allocated from the 'pods' secondary range)."
  type        = number
  default     = 64

  validation {
    condition     = var.default_max_pods_per_node >= 8 && var.default_max_pods_per_node <= 256
    error_message = "default_max_pods_per_node must be between 8 and 256."
  }
}

variable "enable_private_endpoint" {
  description = "Disable external IP access to the Kubernetes API endpoint completely so it is reachable only over private VPC networking."
  type        = bool
  default     = false
}

variable "enable_master_global_access" {
  description = "Allow private access to the Kubernetes control plane from any region connected to the shared environment VPC."
  type        = bool
  default     = true
}

variable "master_ipv4_cidr_block" {
  description = "Optional /28 RFC1918 CIDR block for legacy VPC-peered private control plane. When null (default), GKE uses Private Service Connect with no /28 CIDR management."
  type        = string
  default     = null

  validation {
    condition     = var.master_ipv4_cidr_block == null || (can(cidrhost(var.master_ipv4_cidr_block, 0)) && endswith(var.master_ipv4_cidr_block, "/28"))
    error_message = "master_ipv4_cidr_block must be null or a valid /28 IPv4 CIDR block."
  }
}

variable "authorized_networks" {
  description = "CIDR blocks (such as corporate VPNs, bastions, or CI runners) permitted to reach the Kubernetes control plane endpoint."
  type = list(object({
    cidr_block   = string
    display_name = string
  }))
  default = []

  validation {
    condition     = alltrue([for n in var.authorized_networks : can(cidrhost(n.cidr_block, 0))])
    error_message = "Every entry in authorized_networks must have a valid IPv4/IPv6 CIDR block."
  }
}

variable "enable_cilium_clusterwide_network_policy" {
  description = "Enable CiliumClusterwideNetworkPolicy CRDs on Dataplane V2 so the platform team can enforce cluster-wide baseline network guardrails across product team namespaces."
  type        = bool
  default     = true
}

variable "enable_gateway_api" {
  description = "Enable the managed GKE Gateway API controller (CHANNEL_STANDARD) for shared multi-team ingress routing."
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# Node Pools & Autoscaling
# -----------------------------------------------------------------------------

variable "node_pools" {
  description = "Managed GKE Standard node pools. Defaults to a multi-zonal general-purpose production node pool; add entries for specialized machine types, Spot pools, labels, or taints."
  type = map(object({
    machine_type         = optional(string, "n2-standard-4")
    disk_size_gb         = optional(number, 100)
    disk_type            = optional(string, "pd-balanced")
    spot                 = optional(bool, false)
    enable_gvnic         = optional(bool, true)
    total_min_node_count = optional(number, 3)
    total_max_node_count = optional(number, 12)
    location_policy      = optional(string, "BALANCED")
    max_pods_per_node    = optional(number)
    pod_pids_limit       = optional(number, 4096)
    max_surge            = optional(number, 1)
    max_unavailable      = optional(number, 0)
    node_locations       = optional(list(string))
    labels               = optional(map(string), {})
    network_tags         = optional(list(string), [])
    taints = optional(list(object({
      key    = string
      value  = string
      effect = string
    })), [])
  }))

  default = {
    general = {
      machine_type         = "n2-standard-4"
      disk_size_gb         = 100
      disk_type            = "pd-balanced"
      spot                 = false
      enable_gvnic         = true
      total_min_node_count = 3
      total_max_node_count = 12
      location_policy      = "BALANCED"
      pod_pids_limit       = 4096
      max_surge            = 1
      max_unavailable      = 0
    }
  }

  validation {
    condition     = length(var.node_pools) >= 1
    error_message = "At least one node pool must be configured in node_pools."
  }

  validation {
    condition = alltrue([
      for name, _ in var.node_pools :
      can(regex("^[a-z]([a-z0-9-]{0,38}[a-z0-9])?$", name))
    ])
    error_message = "Node pool names must be 1-40 characters, start with a lowercase letter, and contain only lowercase letters, digits, and hyphens."
  }

  validation {
    condition = alltrue([
      for _, pool in var.node_pools :
      pool.total_min_node_count >= 0 &&
      pool.total_max_node_count >= 1 &&
      pool.total_max_node_count >= pool.total_min_node_count
    ])
    error_message = "Each node pool must have total_min_node_count >= 0, total_max_node_count >= 1, and total_max_node_count >= total_min_node_count."
  }

  validation {
    condition     = anytrue([for _, pool in var.node_pools : !pool.spot && pool.total_min_node_count >= 1])
    error_message = "At least one non-Spot node pool must have total_min_node_count >= 1 to reliably host critical cluster system pods."
  }

  validation {
    condition = alltrue([
      for _, pool in var.node_pools :
      contains(["pd-standard", "pd-balanced", "pd-ssd", "hyperdisk-balanced"], pool.disk_type)
    ])
    error_message = "Node pool disk_type must be one of 'pd-standard', 'pd-balanced', 'pd-ssd', or 'hyperdisk-balanced'."
  }

  validation {
    condition = alltrue([
      for _, pool in var.node_pools :
      contains(["BALANCED", "ANY"], pool.location_policy)
    ])
    error_message = "Node pool location_policy must be 'BALANCED' or 'ANY'."
  }

  validation {
    condition = alltrue([
      for _, pool in var.node_pools :
      pool.pod_pids_limit >= 1024 && pool.pod_pids_limit <= 4194304
    ])
    error_message = "Node pool pod_pids_limit must be between 1024 and 4194304."
  }

  validation {
    condition = alltrue([
      for _, pool in var.node_pools :
      pool.max_surge >= 0 && pool.max_unavailable >= 0 && (pool.max_surge + pool.max_unavailable) >= 1
    ])
    error_message = "Each node pool must set non-negative max_surge and max_unavailable with max_surge + max_unavailable >= 1."
  }

  validation {
    condition = alltrue(flatten([
      for _, pool in var.node_pools : [
        for t in pool.taints :
        contains(["NO_SCHEDULE", "PREFER_NO_SCHEDULE", "NO_EXECUTE"], t.effect)
      ]
    ]))
    error_message = "Node taint effect must be 'NO_SCHEDULE', 'PREFER_NO_SCHEDULE', or 'NO_EXECUTE'."
  }
}

variable "autoscaling_profile" {
  description = "Cluster Autoscaler bin-packing profile ('BALANCED' or 'OPTIMIZE_UTILIZATION')."
  type        = string
  default     = "BALANCED"

  validation {
    condition     = contains(["BALANCED", "OPTIMIZE_UTILIZATION"], var.autoscaling_profile)
    error_message = "autoscaling_profile must be 'BALANCED' or 'OPTIMIZE_UTILIZATION'."
  }
}

variable "enable_vertical_pod_autoscaling" {
  description = "Enable Vertical Pod Autoscaling (VPA) for container resource recommendations and right-sizing."
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# Security, IAM & Workload Identity (Pub/Sub, Cloud Storage, Cloud SQL, etc.)
# -----------------------------------------------------------------------------

variable "additional_node_service_account_roles" {
  description = "Additional project-level IAM roles to grant the cluster's dedicated least-privilege node service account."
  type        = list(string)
  default     = []
}

variable "workload_identities" {
  description = "Optional map of Workload Identity bindings allowing Kubernetes ServiceAccounts in product team namespaces to access Google Cloud APIs (Pub/Sub, Cloud Storage, Cloud SQL, etc.). If gcp_service_account_email is omitted, a dedicated GCP service account is created."
  type = map(object({
    namespace                 = string
    k8s_service_account       = string
    gcp_service_account_email = optional(string)
    display_name              = optional(string)
    project_roles             = optional(list(string), [])
  }))
  default = {}

  validation {
    condition = alltrue([
      for k, wi in var.workload_identities :
      can(regex("^[a-z]([a-z0-9-]{0,28}[a-z0-9])?$", k)) &&
      length(wi.namespace) > 0 &&
      length(wi.k8s_service_account) > 0
    ])
    error_message = "Each workload_identities key must be 1-30 lowercase alphanumeric/hyphen characters, with non-empty namespace and k8s_service_account."
  }
}

variable "rbac_security_group" {
  description = "Optional Google Groups for RBAC security group email (for example, 'gke-security-groups@example.com') to manage multi-team RBAC via Google Groups."
  type        = string
  default     = null
}

variable "etcd_kms_key_name" {
  description = "Optional Cloud KMS CryptoKey resource ID ('projects/.../locations/.../keyRings/.../cryptoKeys/...') for application-layer Kubernetes Secret encryption in etcd."
  type        = string
  default     = null
}

variable "enable_binary_authorization" {
  description = "Enforce Google Cloud Binary Authorization policy on container images deployed to the cluster."
  type        = bool
  default     = false
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

variable "vulnerability_scanning_mode" {
  description = "GKE workload OS/container vulnerability scanning mode ('VULNERABILITY_BASIC', 'VULNERABILITY_ENTERPRISE', or 'VULNERABILITY_DISABLED')."
  type        = string
  default     = "VULNERABILITY_BASIC"

  validation {
    condition     = contains(["VULNERABILITY_BASIC", "VULNERABILITY_ENTERPRISE", "VULNERABILITY_DISABLED"], var.vulnerability_scanning_mode)
    error_message = "vulnerability_scanning_mode must be 'VULNERABILITY_BASIC', 'VULNERABILITY_ENTERPRISE', or 'VULNERABILITY_DISABLED'."
  }
}

# -----------------------------------------------------------------------------
# Maintenance Windows, Add-ons & Observability
# -----------------------------------------------------------------------------

variable "maintenance_window" {
  description = "Recurring off-peak maintenance window (RFC3339 timestamps and RFC5545 RRULE). Defaults to Tue/Wed/Thu 05:00-10:00 UTC (off-peak overnight across US time zones, providing 60h per 28 days)."
  type = object({
    start_time = optional(string, "2025-01-07T05:00:00Z")
    end_time   = optional(string, "2025-01-07T10:00:00Z")
    recurrence = optional(string, "FREQ=WEEKLY;BYDAY=TU,WE,TH")
  })
  default = {}
}

variable "maintenance_exclusions" {
  description = "Optional maintenance blackout windows for peak business events or change freezes."
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
    error_message = "Each maintenance_exclusions scope must be 'NO_UPGRADES', 'NO_MINOR_UPGRADES', or 'NO_MINOR_OR_NODE_UPGRADES'."
  }
}

variable "notification_pubsub_topic" {
  description = "Optional Pub/Sub topic ID ('projects/<project>/topics/<topic>') to receive GKE upgrade, security bulletin, and deprecation notifications."
  type        = string
  default     = null
}

variable "enable_gcs_fuse_csi_driver" {
  description = "Enable the Cloud Storage FUSE CSI driver so workloads can mount GCS buckets securely via Workload Identity."
  type        = bool
  default     = true
}

variable "enable_secret_manager_addon" {
  description = "Enable the GKE Secret Manager add-on (Secret Store CSI integration with Google Secret Manager)."
  type        = bool
  default     = true
}

variable "enable_backup_agent" {
  description = "Enable the Backup for GKE cluster agent for stateful workload and namespace backup/restore."
  type        = bool
  default     = true
}

variable "enable_nodelocal_dnscache" {
  description = "Enable NodeLocal DNSCache to improve cluster DNS latency and resilience under high connection rates."
  type        = bool
  default     = true
}

variable "enable_cost_allocation" {
  description = "Enable GKE Cost Allocation to break down cluster spend by product team namespace and Kubernetes labels in Cloud Billing."
  type        = bool
  default     = true
}

variable "enable_managed_prometheus" {
  description = "Enable Google Cloud Managed Service for Prometheus for workload and cluster metrics."
  type        = bool
  default     = true
}

variable "enable_datapath_observability" {
  description = "Enable Dataplane V2 flow metrics and Hubble network observability relay."
  type        = bool
  default     = true
}

variable "logging_enabled_components" {
  description = "GKE components exporting logs to Cloud Logging."
  type        = list(string)
  default     = ["SYSTEM_COMPONENTS", "WORKLOADS"]

  validation {
    condition = alltrue([
      for c in var.logging_enabled_components :
      contains(["SYSTEM_COMPONENTS", "WORKLOADS", "APISERVER", "SCHEDULER", "CONTROLLER_MANAGER", "KCP_SSHD", "KCP_CONNECTION", "KCP_HPA"], c)
    ])
    error_message = "logging_enabled_components contains an unsupported GKE logging component."
  }
}

variable "monitoring_enabled_components" {
  description = "GKE components exporting metrics to Cloud Monitoring."
  type        = list(string)
  default = [
    "SYSTEM_COMPONENTS",
    "STORAGE",
    "POD",
    "DEPLOYMENT",
    "STATEFULSET",
    "DAEMONSET",
    "HPA",
    "CADVISOR",
    "KUBELET",
  ]

  validation {
    condition = alltrue([
      for c in var.monitoring_enabled_components :
      contains([
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
        "KUBELET",
        "CADVISOR",
        "DCGM",
        "JOBSET",
      ], c)
    ])
    error_message = "monitoring_enabled_components contains an unsupported GKE monitoring component."
  }
}
