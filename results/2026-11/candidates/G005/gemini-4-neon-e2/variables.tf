################################################################################
# Required Inputs (cluster-specific)
################################################################################

variable "project_id" {
  description = "Google Cloud project ID where the network team's VPCs live and this GKE cluster will be created."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "project_id must be a valid Google Cloud project ID (6-30 lowercase letters, digits, or hyphens)."
  }
}

variable "cluster_name" {
  description = "Unique name for this GKE cluster (e.g., 'core-us-central1'). Must be unique within the region and follow RFC 1035 naming rules."
  type        = string

  validation {
    condition     = can(regex("^[a-z]([a-z0-9-]{0,38}[a-z0-9])?$", var.cluster_name))
    error_message = "cluster_name must be 1-40 characters, start with a lowercase letter, end with a lowercase letter or digit, and contain only lowercase letters, digits, and hyphens."
  }
}

variable "environment" {
  description = "Target environment ('staging' or 'prod'). Automatically selects the network team's VPC (apps-<environment>) and regional GKE subnet (apps-<environment>-gke-<region>), sets labels, and defaults deletion_protection to true in prod."
  type        = string

  validation {
    condition     = contains(["staging", "prod"], var.environment)
    error_message = "environment must be either 'staging' or 'prod' (matching the apps-staging and apps-prod VPCs)."
  }
}

variable "region" {
  description = "US Google Cloud region for this regional HA cluster (e.g., 'us-central1', 'us-east1', 'us-west1'). Selects the subnet apps-<environment>-gke-<region>."
  type        = string

  validation {
    condition     = can(regex("^us-[a-z]+[0-9]+$", var.region))
    error_message = "region must be a valid US Google Cloud region (e.g., us-central1, us-east1, us-east4, us-west1)."
  }
}

################################################################################
# Networking & Control Plane Access
################################################################################

variable "enable_private_endpoint" {
  description = "When true, disables the public IP control plane endpoint so the Kubernetes API is reachable only from private VPC networks. When false, the public IP endpoint exists but remains blocked unless CIDRs are explicitly added to authorized_networks."
  type        = bool
  default     = false
}

variable "enable_dns_endpoint_external_traffic" {
  description = "Allow IAM-authenticated access to the GKE DNS control plane endpoint from external networks (useful for kubectl without static VPN IP allowlists)."
  type        = bool
  default     = false
}

variable "authorized_networks" {
  description = "CIDR blocks authorized to reach the Kubernetes API control plane (e.g., corporate VPN, bastion, or CI/CD egress CIDRs). Empty by default (fail-closed to the public internet)."
  type = list(object({
    cidr_block   = string
    display_name = string
  }))
  default = []

  validation {
    condition     = alltrue([for n in var.authorized_networks : can(cidrhost(n.cidr_block, 0))])
    error_message = "Each entry in authorized_networks must have a valid IPv4 CIDR block."
  }
}

variable "enforce_authorized_networks_on_private_endpoint" {
  description = "When true, also restricts internal VPC access to the private control plane endpoint to only the CIDRs listed in authorized_networks."
  type        = bool
  default     = false
}

variable "master_ipv4_cidr_block" {
  description = "Optional /28 RFC1918 CIDR block for legacy VPC-peered control plane networking. Leave null (recommended) to use GKE Private Service Connect, avoiding /28 allocation and overlap across clusters in the same VPC."
  type        = string
  default     = null

  validation {
    condition     = var.master_ipv4_cidr_block == null || can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}/28$", var.master_ipv4_cidr_block))
    error_message = "master_ipv4_cidr_block must be a valid /28 IPv4 CIDR block (or null for Private Service Connect)."
  }
}

variable "additional_control_plane_webhook_ports" {
  description = "Optional extra TCP ports to allow from the VPC-peered control plane CIDR to worker nodes for admission webhooks (e.g., ['8443', '9443']). Only creates a firewall rule when master_ipv4_cidr_block is set."
  type        = list(string)
  default     = []
}

variable "node_zones" {
  description = "Optional explicit list of zones within var.region for worker nodes. Leave empty to automatically spread nodes across all zones in the region (3 zones for regional HA)."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for z in var.node_zones : startswith(z, "${var.region}-")])
    error_message = "All entries in node_zones must belong to var.region (e.g., '${var.region}-a')."
  }
}

variable "default_max_pods_per_node" {
  description = "Cluster-wide default maximum pods per node. Defaults to 64 (/25 per node), doubling pod IP capacity across clusters sharing the subnet's /17 pods range compared to GKE's default of 110 (/24)."
  type        = number
  default     = 64

  validation {
    condition     = var.default_max_pods_per_node >= 8 && var.default_max_pods_per_node <= 110
    error_message = "default_max_pods_per_node must be between 8 and 110."
  }
}

variable "enable_intranode_visibility" {
  description = "Route pod-to-pod traffic on the same node through the VPC network so VPC Flow Logs and firewall rules observe intra-node traffic."
  type        = bool
  default     = true
}

variable "enable_cilium_clusterwide_network_policy" {
  description = "Enable CiliumClusterwideNetworkPolicy on Dataplane V2 so the platform team can enforce cluster-wide network guardrails across all product team namespaces."
  type        = bool
  default     = true
}

variable "enable_fqdn_network_policy" {
  description = "Enable FQDN-based egress NetworkPolicies on Dataplane V2."
  type        = bool
  default     = false
}

################################################################################
# Kubernetes Lifecycle, Operations & Maintenance
################################################################################

variable "release_channel" {
  description = "GKE release channel governing automated control plane and node upgrades ('RAPID', 'REGULAR', 'STABLE', or 'EXTENDED'). REGULAR is recommended for production balance of security patches and stability."
  type        = string
  default     = "REGULAR"

  validation {
    condition     = contains(["RAPID", "REGULAR", "STABLE", "EXTENDED"], var.release_channel)
    error_message = "release_channel must be one of: RAPID, REGULAR, STABLE, EXTENDED."
  }
}

variable "maintenance_window" {
  description = "Recurring maintenance window for automated GKE upgrades (RFC 3339 timestamps and RFC 5545 RRULE). Must provide at least 48 hours of maintenance availability per 32-day rolling window with >=4h per window. Defaults to Saturday and Sunday 02:00-10:00 UTC (64h+ per 32 days, off-peak weekends)."
  type = object({
    start_time = string
    end_time   = string
    recurrence = string
  })
  default = {
    start_time = "2025-01-04T02:00:00Z"
    end_time   = "2025-01-04T10:00:00Z"
    recurrence = "FREQ=WEEKLY;BYDAY=SA,SU"
  }
}

variable "maintenance_exclusions" {
  description = "Optional temporary maintenance freeze windows (e.g., peak traffic events or incident freezes). Scope can be 'NO_UPGRADES', 'NO_MINOR_UPGRADES', or 'NO_MINOR_OR_NODE_UPGRADES'."
  type = list(object({
    name       = string
    start_time = string
    end_time   = string
    scope      = optional(string, "NO_UPGRADES")
  }))
  default = []

  validation {
    condition = alltrue([
      for e in var.maintenance_exclusions :
      contains(["NO_UPGRADES", "NO_MINOR_UPGRADES", "NO_MINOR_OR_NODE_UPGRADES"], e.scope)
    ])
    error_message = "maintenance_exclusions scope must be NO_UPGRADES, NO_MINOR_UPGRADES, or NO_MINOR_OR_NODE_UPGRADES."
  }
}

variable "deletion_protection" {
  description = "Prevent accidental cluster deletion via OpenTofu/API. Defaults to true when environment == 'prod' and false when environment == 'staging' if left null."
  type        = bool
  default     = null
}

variable "autoscaling_profile" {
  description = "Cluster Autoscaler scheduling profile: 'BALANCED' (default) or 'OPTIMIZE_UTILIZATION' (packs workloads more aggressively to reduce idle capacity)."
  type        = string
  default     = "BALANCED"

  validation {
    condition     = contains(["BALANCED", "OPTIMIZE_UTILIZATION"], var.autoscaling_profile)
    error_message = "autoscaling_profile must be BALANCED or OPTIMIZE_UTILIZATION."
  }
}

variable "enable_vertical_pod_autoscaling" {
  description = "Enable Vertical Pod Autoscaler (VPA) to help product teams right-size pod CPU and memory requests."
  type        = bool
  default     = true
}

variable "enable_cost_allocation" {
  description = "Enable GKE Cost Allocation to break down cluster compute costs by Kubernetes namespace and labels in Cloud Billing for shared multi-team clusters."
  type        = bool
  default     = true
}

variable "notification_pubsub_topic" {
  description = "Optional full Pub/Sub topic resource name (projects/<project>/topics/<topic>) to receive GKE upgrade and security bulletin notifications."
  type        = string
  default     = null

  validation {
    condition     = var.notification_pubsub_topic == null || can(regex("^projects/[^/]+/topics/[^/]+$", var.notification_pubsub_topic))
    error_message = "notification_pubsub_topic must be in the format 'projects/<project_id>/topics/<topic_name>'."
  }
}

################################################################################
# Security, Governance & IAM
################################################################################

variable "security_group" {
  description = "Optional Google Group email (e.g., 'gke-security-groups@company.com') for GKE RBAC with Google Groups, allowing namespace-scoped access management per product team."
  type        = string
  default     = null

  validation {
    condition     = var.security_group == null || can(regex("^gke-security-groups@.+$", var.security_group))
    error_message = "Google requires the RBAC security group to be named 'gke-security-groups@<your-domain>'."
  }
}

variable "database_encryption_kms_key_id" {
  description = "Optional Cloud KMS CryptoKey ID (projects/.../locations/.../keyRings/.../cryptoKeys/...) for customer-managed application-layer etcd secret encryption (CMEK). When null, Google-managed encryption is used."
  type        = string
  default     = null

  validation {
    condition     = var.database_encryption_kms_key_id == null || can(regex("^projects/[^/]+/locations/[^/]+/keyRings/[^/]+/cryptoKeys/[^/]+$", var.database_encryption_kms_key_id))
    error_message = "database_encryption_kms_key_id must be a full Cloud KMS CryptoKey resource ID."
  }
}

variable "binary_authorization_mode" {
  description = "Binary Authorization evaluation mode ('DISABLED' or 'PROJECT_SINGLETON_POLICY_ENFORCE'). Enable once CI/CD image attestation policies are configured in the project."
  type        = string
  default     = "DISABLED"

  validation {
    condition     = contains(["DISABLED", "PROJECT_SINGLETON_POLICY_ENFORCE"], var.binary_authorization_mode)
    error_message = "binary_authorization_mode must be DISABLED or PROJECT_SINGLETON_POLICY_ENFORCE."
  }
}

variable "security_posture_mode" {
  description = "GKE Security Posture configuration scanning mode ('BASIC', 'ENTERPRISE', or 'DISABLED')."
  type        = string
  default     = "BASIC"

  validation {
    condition     = contains(["BASIC", "ENTERPRISE", "DISABLED"], var.security_posture_mode)
    error_message = "security_posture_mode must be BASIC, ENTERPRISE, or DISABLED."
  }
}

variable "vulnerability_scanning_mode" {
  description = "GKE workload container vulnerability scanning mode ('VULNERABILITY_BASIC', 'VULNERABILITY_ENTERPRISE', or 'VULNERABILITY_DISABLED')."
  type        = string
  default     = "VULNERABILITY_BASIC"

  validation {
    condition     = contains(["VULNERABILITY_BASIC", "VULNERABILITY_ENTERPRISE", "VULNERABILITY_DISABLED"], var.vulnerability_scanning_mode)
    error_message = "vulnerability_scanning_mode must be VULNERABILITY_BASIC, VULNERABILITY_ENTERPRISE, or VULNERABILITY_DISABLED."
  }
}

variable "enable_secret_manager_addon" {
  description = "Enable the GKE Secret Manager add-on so workloads can mount secrets from Google Cloud Secret Manager via Workload Identity. Requires the secretmanager.googleapis.com API to be enabled in the project."
  type        = bool
  default     = false
}

variable "enable_image_streaming" {
  description = "Enable GKE Image Streaming (GCFS) on node pools to accelerate container startup from Artifact Registry. Requires the containerfilesystem.googleapis.com API to be enabled in the project."
  type        = bool
  default     = false
}

variable "artifact_registry_project_ids" {
  description = "Optional list of additional GCP project IDs (e.g., a shared CI/CD image registry project) where the cluster's node service account is granted roles/artifactregistry.reader."
  type        = list(string)
  default     = []
}

################################################################################
# Observability & Add-ons
################################################################################

variable "logging_components" {
  description = "GKE components exporting logs to Cloud Logging."
  type        = list(string)
  default     = ["SYSTEM_COMPONENTS", "WORKLOADS"]
}

variable "monitoring_components" {
  description = "GKE components exporting metrics to Cloud Monitoring."
  type        = list(string)
  default = [
    "SYSTEM_COMPONENTS",
    "DAEMONSET",
    "DEPLOYMENT",
    "STATEFULSET",
    "STORAGE",
    "HPA",
    "POD",
    "CADVISOR",
    "KUBELET",
  ]
}

variable "enable_managed_prometheus" {
  description = "Enable Google Cloud Managed Service for Prometheus (GMP) for scraping PodMonitoring/ClusterPodMonitoring metrics."
  type        = bool
  default     = true
}

variable "enable_gcs_fuse_csi_driver" {
  description = "Enable the Cloud Storage FUSE CSI driver so workloads can mount GCS buckets directly as Kubernetes volumes via Workload Identity."
  type        = bool
  default     = true
}

variable "enable_gce_pd_csi_driver" {
  description = "Enable the Compute Engine Persistent Disk CSI driver for stateful Kubernetes workloads."
  type        = bool
  default     = true
}

variable "enable_dns_cache" {
  description = "Enable NodeLocal DNSCache to reduce kube-dns contention and improve DNS lookup latency and reliability in busy multi-team clusters."
  type        = bool
  default     = true
}

variable "gateway_api_channel" {
  description = "Kubernetes Gateway API release channel ('CHANNEL_STANDARD' or 'CHANNEL_DISABLED'). Recommended for multi-team shared Gateway / per-team HTTPRoute ingress."
  type        = string
  default     = "CHANNEL_STANDARD"

  validation {
    condition     = contains(["CHANNEL_STANDARD", "CHANNEL_DISABLED"], var.gateway_api_channel)
    error_message = "gateway_api_channel must be CHANNEL_STANDARD or CHANNEL_DISABLED."
  }
}

################################################################################
# Node Pools
################################################################################

variable "system_node_pool" {
  description = "Configuration for the dedicated system node pool hosting GKE-managed system components (tainted with components.gke.io/gke-managed-components=true:NoSchedule so product workloads cannot starve kube-dns or cluster agents)."
  type = object({
    machine_type       = optional(string, "e2-standard-2")
    min_count_per_zone = optional(number, 1)
    max_count_per_zone = optional(number, 3)
    disk_size_gb       = optional(number, 100)
    disk_type          = optional(string, "pd-balanced")
    max_pods_per_node  = optional(number, 64)
  })
  default = {}

  validation {
    condition     = var.system_node_pool.min_count_per_zone >= 1 && var.system_node_pool.max_count_per_zone >= var.system_node_pool.min_count_per_zone
    error_message = "system_node_pool must have min_count_per_zone >= 1 and max_count_per_zone >= min_count_per_zone."
  }
}

variable "workload_node_pools" {
  description = <<-EOT
    Map of workload node pools for product teams. Defaults to a single resilient general-purpose pool ('general').
    Add or customize pools for specialized workloads (e.g., high-memory, Spot/batch, or gVisor-sandboxed untrusted workloads).
    Spot pools automatically receive the 'cloud.google.com/gke-spot=true:NO_SCHEDULE' taint and ANY zone location_policy unless overridden.
  EOT
  type = map(object({
    machine_type       = optional(string, "e2-standard-4")
    min_count_per_zone = optional(number, 1)
    max_count_per_zone = optional(number, 5)
    disk_size_gb       = optional(number, 100)
    disk_type          = optional(string, "pd-balanced")
    spot               = optional(bool, false)
    max_pods_per_node  = optional(number, null)
    enable_gvisor      = optional(bool, false)
    upgrade_strategy   = optional(string, "SURGE")
    max_surge          = optional(number, 1)
    max_unavailable    = optional(number, 0)
    logging_variant    = optional(string, "DEFAULT")
    labels             = optional(map(string), {})
    tags               = optional(list(string), [])
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
    condition     = length(var.workload_node_pools) > 0
    error_message = "At least one workload node pool must be defined in workload_node_pools."
  }

  validation {
    condition     = !contains(keys(var.workload_node_pools), "system")
    error_message = "'system' is reserved for the dedicated system_node_pool; choose another name in workload_node_pools."
  }

  validation {
    condition = alltrue([
      for k, v in var.workload_node_pools :
      can(regex("^[a-z]([a-z0-9-]{0,20}[a-z0-9])?$", k))
    ])
    error_message = "Workload node pool keys must be 1-22 lowercase alphanumeric/hyphen characters starting with a letter."
  }

  validation {
    condition = alltrue([
      for k, v in var.workload_node_pools :
      v.min_count_per_zone >= 0 && v.max_count_per_zone >= v.min_count_per_zone && v.max_count_per_zone >= 1
    ])
    error_message = "Each workload node pool must satisfy min_count_per_zone >= 0, max_count_per_zone >= min_count_per_zone, and max_count_per_zone >= 1."
  }

  validation {
    condition = alltrue([
      for k, v in var.workload_node_pools :
      contains(["SURGE", "BLUE_GREEN"], v.upgrade_strategy)
    ])
    error_message = "Node pool upgrade_strategy must be SURGE or BLUE_GREEN."
  }

  validation {
    condition = alltrue([
      for k, v in var.workload_node_pools :
      contains(["DEFAULT", "MAX_THROUGHPUT"], v.logging_variant)
    ])
    error_message = "Node pool logging_variant must be DEFAULT or MAX_THROUGHPUT."
  }
}

################################################################################
# Metadata & Labels
################################################################################

variable "labels" {
  description = "Additional GCP labels applied to the cluster and node pool VMs (merged with standard platform labels: environment, cluster, managed-by)."
  type        = map(string)
  default     = {}
}
