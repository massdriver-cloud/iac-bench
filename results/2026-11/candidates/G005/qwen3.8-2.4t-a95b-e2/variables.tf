# -----------------------------------------------------------------------------
# Cluster identity: the only inputs that are truly specific to each cluster.
# Everything else in this module has an opinionated, production-ready default.
# -----------------------------------------------------------------------------

variable "project_id" {
  description = "Google Cloud project that will own the cluster. This must be the same project that contains the environment VPC (the network team's VPCs live here)."
  type        = string
}

variable "cluster_name" {
  description = "Name of the GKE cluster, e.g. \"payments-staging\". Must be unique within the project."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,39}$", var.cluster_name))
    error_message = "cluster_name must start with a lowercase letter, contain only lowercase letters, digits and hyphens, and be at most 40 characters."
  }
}

variable "region" {
  description = "Google Cloud region for the cluster (one of our US regions). The cluster is regional: its control plane and nodes are spread across all zones of this region."
  type        = string
}

variable "network_name" {
  description = "Name of the environment VPC owned by the network team (\"apps-staging\" or \"apps-prod\"). The cluster is deployed into this VPC."
  type        = string
}

# -----------------------------------------------------------------------------
# Networking
# -----------------------------------------------------------------------------

variable "subnetwork_name" {
  description = "Subnet to deploy the cluster into. Defaults to the network team's naming convention: \"<network_name>-gke-<region>\". Override only if the subnet was named differently."
  type        = string
  default     = null
}

variable "pods_range_name" {
  description = "Name of the subnet's secondary range used for pod IPs. The network team's convention is \"pods\"."
  type        = string
  default     = "pods"
}

variable "services_range_name" {
  description = "Name of the subnet's secondary range used for Service cluster IPs. The network team's convention is \"services\"."
  type        = string
  default     = "services"
}

variable "enable_private_endpoint" {
  description = "If true, the control plane has only a private IP and is reachable solely from inside the VPC (e.g. a bastion). If false (default), the control plane also has a public endpoint, but it is unreachable from the internet until master_authorized_networks is populated."
  type        = bool
  default     = false
}

variable "master_authorized_networks" {
  description = "CIDR blocks allowed to reach the control plane's public endpoint (e.g. office/VPN ranges). Leave empty to block all internet access to the control plane. Access from within the VPC is always allowed."
  type = list(object({
    cidr_block   = string
    display_name = optional(string)
  }))
  default = []
}

variable "master_ipv4_cidr_block" {
  description = "RFC 1918 CIDR for the control plane's private IP. Defaults to null, letting GKE pick a free /28 automatically (recommended: several clusters share each VPC)."
  type        = string
  default     = null

  validation {
    condition     = var.master_ipv4_cidr_block == null || can(cidrnetmask(var.master_ipv4_cidr_block))
    error_message = "master_ipv4_cidr_block must be a valid CIDR block or null."
  }
}

# -----------------------------------------------------------------------------
# Kubernetes versioning and upgrades
# -----------------------------------------------------------------------------

variable "release_channel" {
  description = "GKE release channel. STABLE is the default for production; REGULAR if a cluster needs newer features sooner."
  type        = string
  default     = "STABLE"

  validation {
    condition     = contains(["STABLE", "REGULAR", "RAPID", "UNSPECIFIED"], var.release_channel)
    error_message = "release_channel must be one of: STABLE, REGULAR, RAPID, UNSPECIFIED."
  }
}

variable "kubernetes_version" {
  description = "Pin the control plane to a specific Kubernetes version. Defaults to null, meaning the release channel decides (recommended)."
  type        = string
  default     = null
}

variable "maintenance_window" {
  description = "Recurring maintenance/upgrade window (times are RFC 3339; only the time-of-day plus the recurrence rule matter). Default: Sundays 02:00-08:00 UTC."
  type = object({
    start_time = string
    end_time   = string
    recurrence = string
  })
  default = {
    start_time = "2024-01-07T02:00:00Z"
    end_time   = "2024-01-07T08:00:00Z"
    recurrence = "FREQ=WEEKLY;BYDAY=SU"
  }
}

# -----------------------------------------------------------------------------
# Node pool
# -----------------------------------------------------------------------------

variable "node_machine_type" {
  description = "Machine type for the default node pool."
  type        = string
  default     = "e2-standard-4"
}

variable "node_disk_size_gb" {
  description = "Boot disk size (GB) for each node."
  type        = number
  default     = 100
}

variable "node_disk_type" {
  description = "Boot disk type for each node."
  type        = string
  default     = "pd-balanced"
}

variable "min_nodes_per_zone" {
  description = "Minimum number of nodes per zone for the default pool (cluster autoscaler floor). With a regional cluster this is multiplied by the number of zones."
  type        = number
  default     = 1
}

variable "max_nodes_per_zone" {
  description = "Maximum number of nodes per zone for the default pool (cluster autoscaler ceiling)."
  type        = number
  default     = 5
}

variable "node_labels" {
  description = "Extra Kubernetes labels applied to every node in the default pool."
  type        = map(string)
  default     = {}
}

variable "node_network_tags" {
  description = "Compute Engine network tags applied to nodes, e.g. to match network-team firewall rules. GKE creates its own firewall rules automatically."
  type        = list(string)
  default     = []
}

variable "node_sa_roles" {
  description = "Project roles granted to the module-managed node service account. Defaults follow Google's least-privilege guidance for GKE nodes (log/metric writers plus image pulls from Artifact Registry / gCR). Workloads should NOT use this identity: they get their own service accounts via Workload Identity."
  type        = list(string)
  default = [
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/monitoring.viewer",
    "roles/stackdriver.resourceMetadata.writer",
    "roles/artifactregistry.reader",
    "roles/storage.objectViewer",
  ]
}

# -----------------------------------------------------------------------------
# Cluster features and hardening
# -----------------------------------------------------------------------------

variable "datapath_provider" {
  description = "Cluster dataplane. ADVANCED_DATAPATH (Dataplane V2) is the default: it provides built-in network policy enforcement and observability."
  type        = string
  default     = "ADVANCED_DATAPATH"

  validation {
    condition     = contains(["ADVANCED_DATAPATH", "LEGACY_DATAPATH"], var.datapath_provider)
    error_message = "datapath_provider must be ADVANCED_DATAPATH or LEGACY_DATAPATH."
  }
}

variable "dns_cache_enabled" {
  description = "Enable NodeLocal DNSCache on nodes (reduces DNS latency and load)."
  type        = bool
  default     = true
}

variable "enable_l4_ilb_subsetting" {
  description = "Enable L4 ILB subsetting so internal load balancers target node subsets instead of whole instance groups."
  type        = bool
  default     = true
}

variable "enable_vertical_pod_autoscaling" {
  description = "Enable the Vertical Pod Autoscaling addon (only acts on workloads that create VPA objects)."
  type        = bool
  default     = true
}

variable "logging_components" {
  description = "Cluster logging ingestion components. Add \"WORKLOADS\" to also ingest application stdout/stderr into Cloud Logging (cost impact)."
  type        = list(string)
  default     = ["SYSTEM_COMPONENTS"]
}

variable "monitoring_components" {
  description = "Cluster monitoring ingestion components. APISERVER, CONTROLLER_MANAGER and SCHEDULER can be added alongside SYSTEM_COMPONENTS."
  type        = list(string)
  default     = ["SYSTEM_COMPONENTS"]
}

variable "security_posture_mode" {
  description = "GKE Security Posture mode: BASIC enables posture checks, ENTERPRISE adds continuous compliance. Use DISABLED to turn it off."
  type        = string
  default     = "BASIC"

  validation {
    condition     = contains(["DISABLED", "BASIC", "ENTERPRISE"], var.security_posture_mode)
    error_message = "security_posture_mode must be DISABLED, BASIC or ENTERPRISE."
  }
}

variable "security_posture_vulnerability_mode" {
  description = "GKE Security Posture vulnerability scanning: VULNERABILITY_BASIC scans nodes, VULNERABILITY_ENTERPRISE also scans workload images."
  type        = string
  default     = "VULNERABILITY_BASIC"

  validation {
    condition     = contains(["VULNERABILITY_DISABLED", "VULNERABILITY_BASIC", "VULNERABILITY_ENTERPRISE"], var.security_posture_vulnerability_mode)
    error_message = "security_posture_vulnerability_mode must be VULNERABILITY_DISABLED, VULNERABILITY_BASIC or VULNERABILITY_ENTERPRISE."
  }
}

variable "binary_authorization_mode" {
  description = "Binary Authorization evaluation mode. Set to PROJECT_SINGLETON_POLICY_ENFORCE to enforce image attestation policies defined at project level."
  type        = string
  default     = "DISABLED"

  validation {
    condition     = contains(["DISABLED", "PROJECT_SINGLETON_POLICY_ENFORCE"], var.binary_authorization_mode)
    error_message = "binary_authorization_mode must be DISABLED or PROJECT_SINGLETON_POLICY_ENFORCE."
  }
}

variable "database_encryption_key_name" {
  description = "Fully-qualified Cloud KMS key (projects/*/locations/*/keyRings/*/cryptoKeys/*) used to envelope-encrypt Kubernetes Secrets at rest. Defaults to null (Google-managed encryption)."
  type        = string
  default     = null
}

variable "upgrade_notification_pubsub_topic" {
  description = "Optional Pub/Sub topic (projects/*/topics/*) that receives cluster upgrade/health notifications."
  type        = string
  default     = null
}

variable "cluster_labels" {
  description = "Google Cloud resource labels applied to the cluster (lowercase keys/values, hyphens/underscores)."
  type        = map(string)
  default     = {}
}

variable "deletion_protection" {
  description = "If true, the cluster cannot be destroyed via OpenTofu without first setting this to false. Production default is true."
  type        = bool
  default     = true
}
