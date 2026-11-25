################################################################################
# Required cluster-specific variables
################################################################################

variable "cluster_name" {
  description = "Unique name for the GKE Standard cluster (1-40 lowercase alphanumeric characters or hyphens, starting with a letter and ending with an alphanumeric character)."
  type        = string

  validation {
    condition     = can(regex("^[a-z]([a-z0-9-]{0,38}[a-z0-9])?$", var.cluster_name))
    error_message = "cluster_name must be 1-40 characters of lowercase letters, digits, or hyphens, starting with a letter and ending with a letter or digit."
  }
}

variable "environment" {
  description = "Target environment, selecting the network team's VPC (apps-<environment>) and regional GKE subnet (apps-<environment>-gke-<region>)."
  type        = string

  validation {
    condition     = contains(["staging", "prod"], var.environment)
    error_message = "environment must be either \"staging\" or \"prod\"."
  }
}

variable "region" {
  description = "Google Cloud US region for this regional GKE cluster (for example, us-central1, us-east1, us-west1)."
  type        = string

  validation {
    condition     = can(regex("^us-[a-z]+[0-9]+$", var.region))
    error_message = "region must be a valid Google Cloud US region (e.g., us-central1, us-east1, us-west1)."
  }
}

################################################################################
# Optional project & metadata configuration
################################################################################

variable "project_id" {
  description = "Google Cloud project ID containing both the VPC and the GKE cluster. Defaults to the project configured in the Google provider environment."
  type        = string
  default     = null
}

variable "cluster_description" {
  description = "Human-readable description attached to the GKE cluster resource."
  type        = string
  default     = "Managed production GKE Standard cluster"
}

variable "labels" {
  description = "Additional GCP resource labels applied to the cluster and its node pools."
  type        = map(string)
  default     = {}
}

variable "deletion_protection" {
  description = "Prevent accidental deletion of the GKE cluster via OpenTofu or the GCP API. Keep enabled for production clusters."
  type        = bool
  default     = true
}

################################################################################
# Control plane networking & access control
################################################################################

variable "enable_private_endpoint" {
  description = "Disable the public IP address on the Kubernetes control plane endpoint so API access is private-only (via VPC/VPN/Interconnect/bastion)."
  type        = bool
  default     = true
}

variable "enable_master_global_access" {
  description = "Allow clients in any region of the VPC (or connected via VPN/Interconnect) to reach the private control plane endpoint."
  type        = bool
  default     = true
}

variable "master_ipv4_cidr_block" {
  description = "Optional /28 RFC1918 CIDR block for the private GKE control plane. When null, the module deterministically derives a /28 inside 172.16.0.0/12 from cluster_name and region."
  type        = string
  default     = null

  validation {
    condition     = var.master_ipv4_cidr_block == null || can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}/28$", var.master_ipv4_cidr_block))
    error_message = "master_ipv4_cidr_block must be a valid IPv4 /28 CIDR block (or null for automatic derivation)."
  }
}

variable "master_authorized_networks" {
  description = "CIDR blocks permitted to reach the Kubernetes control plane API (for example, corporate VPN, bastion subnet, or CI/CD runner ranges). When empty, all non-cluster IP access is blocked."
  type = list(object({
    cidr_block   = string
    display_name = string
  }))
  default = []

  validation {
    condition     = alltrue([for n in var.master_authorized_networks : can(cidrnetmask(n.cidr_block))])
    error_message = "Every entry in master_authorized_networks must contain a valid CIDR block."
  }
}

variable "gcp_public_cidrs_access_enabled" {
  description = "Whether Google Cloud public IP addresses may reach the control plane endpoint (only applies when enable_private_endpoint is false)."
  type        = bool
  default     = false
}

variable "default_max_pods_per_node" {
  description = "Default maximum number of pods per node (controls pod CIDR slice allocation per node; 64 uses a /25 per node for efficient IP utilization across the subnet's /17 pods range)."
  type        = number
  default     = 64

  validation {
    condition     = var.default_max_pods_per_node >= 8 && var.default_max_pods_per_node <= 110
    error_message = "default_max_pods_per_node must be between 8 and 110."
  }
}

variable "node_locations" {
  description = "Optional subset of zones in var.region where cluster nodes run. Leave empty to distribute nodes across all available zones in the region (recommended for resilience)."
  type        = list(string)
  default     = []
}

################################################################################
# Security, multi-tenancy & identity
################################################################################

variable "security_group" {
  description = "Optional Google Groups for RBAC security group (for example, gke-security-groups@example.com) used to grant product teams namespace RBAC via Google Groups."
  type        = string
  default     = null
}

variable "database_encryption_key_name" {
  description = "Optional Cloud KMS CryptoKey resource ID (projects/<p>/locations/<l>/keyRings/<kr>/cryptoKeys/<k>) for application-layer encryption of Kubernetes Secrets in etcd."
  type        = string
  default     = null
}

variable "binary_authorization_mode" {
  description = "Binary Authorization enforcement mode for container image verification (DISABLED or PROJECT_SINGLETON_POLICY_ENFORCE)."
  type        = string
  default     = "DISABLED"

  validation {
    condition     = contains(["DISABLED", "PROJECT_SINGLETON_POLICY_ENFORCE"], var.binary_authorization_mode)
    error_message = "binary_authorization_mode must be DISABLED or PROJECT_SINGLETON_POLICY_ENFORCE."
  }
}

variable "security_posture_mode" {
  description = "GKE Security Posture configuration scanning mode (DISABLED, BASIC, or ENTERPRISE)."
  type        = string
  default     = "BASIC"

  validation {
    condition     = contains(["DISABLED", "BASIC", "ENTERPRISE"], var.security_posture_mode)
    error_message = "security_posture_mode must be DISABLED, BASIC, or ENTERPRISE."
  }
}

variable "vulnerability_scanning_mode" {
  description = "GKE Security Posture workload vulnerability scanning mode (VULNERABILITY_DISABLED, VULNERABILITY_BASIC, or VULNERABILITY_ENTERPRISE)."
  type        = string
  default     = "VULNERABILITY_BASIC"

  validation {
    condition     = contains(["VULNERABILITY_DISABLED", "VULNERABILITY_BASIC", "VULNERABILITY_ENTERPRISE"], var.vulnerability_scanning_mode)
    error_message = "vulnerability_scanning_mode must be VULNERABILITY_DISABLED, VULNERABILITY_BASIC, or VULNERABILITY_ENTERPRISE."
  }
}

variable "grant_artifact_registry_reader" {
  description = "Grant roles/artifactregistry.reader in the cluster project to the dedicated node service account so nodes can pull container images from Artifact Registry."
  type        = bool
  default     = true
}

variable "artifact_registry_projects" {
  description = "Optional list of additional GCP project IDs hosting Artifact Registry repositories that cluster nodes should be permitted to pull images from."
  type        = list(string)
  default     = []
}

################################################################################
# Day-2 operations: release channel, maintenance, add-ons & observability
################################################################################

variable "release_channel" {
  description = "GKE release channel governing automatic control plane and node version upgrades (RAPID, REGULAR, STABLE, or UNSPECIFIED)."
  type        = string
  default     = "REGULAR"

  validation {
    condition     = contains(["RAPID", "REGULAR", "STABLE", "UNSPECIFIED"], var.release_channel)
    error_message = "release_channel must be one of RAPID, REGULAR, STABLE, or UNSPECIFIED."
  }
}

variable "maintenance_window" {
  description = "Recurring maintenance window for GKE upgrades. Defaults to Saturday and Sunday 05:00-12:00 UTC (off-peak US hours; 14h/week comfortably exceeds GKE's >=48h per 32-day requirement)."
  type = object({
    start_time = string
    end_time   = string
    recurrence = string
  })
  default = {
    start_time = "2025-01-04T05:00:00Z"
    end_time   = "2025-01-04T12:00:00Z"
    recurrence = "FREQ=WEEKLY;BYDAY=SA,SU"
  }
}

variable "maintenance_exclusions" {
  description = "Optional temporary maintenance freeze windows (for example, during major product launches or peak shopping events)."
  type = list(object({
    exclusion_name = string
    start_time     = string
    end_time       = string
    scope          = optional(string, "NO_MINOR_OR_NODE_UPGRADES")
  }))
  default = []

  validation {
    condition = alltrue([
      for e in var.maintenance_exclusions : contains(
        ["NO_UPGRADES", "NO_MINOR_UPGRADES", "NO_MINOR_OR_NODE_UPGRADES"],
        e.scope
      )
    ])
    error_message = "maintenance_exclusions scope must be NO_UPGRADES, NO_MINOR_UPGRADES, or NO_MINOR_OR_NODE_UPGRADES."
  }
}

variable "notification_topic_id" {
  description = "Optional full Pub/Sub topic resource name (projects/<project>/topics/<topic>) to receive GKE upgrade and security bulletin notifications."
  type        = string
  default     = null
}

variable "autoscaling_profile" {
  description = "Cluster autoscaler profile (BALANCED prioritizes availability and headroom; OPTIMIZE_UTILIZATION packs pods more aggressively)."
  type        = string
  default     = "BALANCED"

  validation {
    condition     = contains(["BALANCED", "OPTIMIZE_UTILIZATION"], var.autoscaling_profile)
    error_message = "autoscaling_profile must be BALANCED or OPTIMIZE_UTILIZATION."
  }
}

variable "logging_components" {
  description = "GKE Cloud Logging components to collect."
  type        = list(string)
  default     = ["SYSTEM_COMPONENTS", "WORKLOADS"]
}

variable "logging_variant" {
  description = "Node logging agent throughput variant (DEFAULT or MAX_THROUGHPUT)."
  type        = string
  default     = "DEFAULT"

  validation {
    condition     = contains(["DEFAULT", "MAX_THROUGHPUT"], var.logging_variant)
    error_message = "logging_variant must be DEFAULT or MAX_THROUGHPUT."
  }
}

variable "monitoring_components" {
  description = "GKE Cloud Monitoring metric components to collect for platform and product team visibility."
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
    "KUBELET",
    "CADVISOR",
  ]
}

variable "enable_managed_prometheus" {
  description = "Enable Google Cloud Managed Service for Prometheus so product teams can scrape workload metrics using PodMonitoring/ClusterPodMonitoring CRDs."
  type        = bool
  default     = true
}

variable "enable_gcs_fuse_csi_driver" {
  description = "Enable the Cloud Storage FUSE CSI driver so workloads can mount Cloud Storage buckets as Kubernetes volumes using Workload Identity."
  type        = bool
  default     = true
}

variable "enable_secret_manager_addon" {
  description = "Enable the Secret Manager add-on so workloads can mount GCP Secret Manager secrets using Workload Identity (requires secretmanager.googleapis.com enabled in the project)."
  type        = bool
  default     = false
}

variable "enable_filestore_csi_driver" {
  description = "Enable the Filestore CSI driver for ReadWriteMany NFS persistent volumes."
  type        = bool
  default     = false
}

variable "enable_backup_agent" {
  description = "Enable the Backup for GKE agent add-on."
  type        = bool
  default     = false
}

################################################################################
# Node pools (dedicated system pool + product team workload pools)
################################################################################

variable "enable_system_node_pool" {
  description = "Provision a dedicated node pool tainted for GKE-managed system components (kube-dns, metrics-server, konnectivity, etc.) to isolate cluster infrastructure from product team workloads."
  type        = bool
  default     = true
}

variable "system_node_pool" {
  description = "Configuration for the dedicated GKE system node pool."
  type = object({
    machine_type           = optional(string, "n2-standard-2")
    min_node_count         = optional(number, 1)
    max_node_count         = optional(number, 3)
    disk_size_gb           = optional(number, 100)
    disk_type              = optional(string, "pd-balanced")
    max_surge              = optional(number, 1)
    max_unavailable        = optional(number, 0)
    enable_image_streaming = optional(bool, false)
    boot_disk_kms_key      = optional(string, null)
  })
  default = {}
}

variable "node_pools" {
  description = "Map of workload node pools to create for product teams. Each key is the logical pool name; defaults to a resilient multi-zone general-purpose pool."
  type = map(object({
    machine_type                       = optional(string, "n2-standard-4")
    min_node_count                     = optional(number, 1)
    max_node_count                     = optional(number, 5)
    location_policy                    = optional(string, "BALANCED")
    node_locations                     = optional(list(string), [])
    disk_size_gb                       = optional(number, 100)
    disk_type                          = optional(string, "pd-balanced")
    image_type                         = optional(string, "COS_CONTAINERD")
    spot                               = optional(bool, false)
    max_pods_per_node                  = optional(number, null)
    pod_pids_limit                     = optional(number, 4096)
    enable_image_streaming             = optional(bool, false)
    enable_gvnic                       = optional(bool, true)
    enable_gvisor                      = optional(bool, false)
    upgrade_strategy                   = optional(string, "SURGE")
    max_surge                          = optional(number, 1)
    max_unavailable                    = optional(number, 0)
    blue_green_batch_soak_duration     = optional(string, "0s")
    blue_green_node_pool_soak_duration = optional(string, "300s")
    blue_green_batch_percentage        = optional(number, 0.25)
    boot_disk_kms_key                  = optional(string, null)
    labels                             = optional(map(string), {})
    tags                               = optional(list(string), [])
    metadata                           = optional(map(string), {})
    taints = optional(list(object({
      key    = string
      value  = string
      effect = string
    })), [])
    guest_accelerators = optional(list(object({
      type  = string
      count = number
      gpu_driver_installation_config = optional(object({
        gpu_driver_version = string
      }), null)
    })), [])
  }))

  default = {
    general = {
      machine_type   = "n2-standard-4"
      min_node_count = 1
      max_node_count = 5
    }
  }

  validation {
    condition     = length(var.node_pools) > 0
    error_message = "At least one workload node pool must be defined in node_pools."
  }

  validation {
    condition = alltrue([
      for k, p in var.node_pools :
      can(regex("^[a-z]([a-z0-9-]{0,26}[a-z0-9])?$", k))
    ])
    error_message = "Each node_pools key must be 1-28 lowercase alphanumeric characters or hyphens, starting with a letter and ending with a letter or digit."
  }

  validation {
    condition = alltrue([
      for p in values(var.node_pools) :
      p.min_node_count >= 0 && p.max_node_count >= 1 && p.max_node_count >= p.min_node_count
    ])
    error_message = "Each node pool must have min_node_count >= 0, max_node_count >= 1, and max_node_count >= min_node_count."
  }

  validation {
    condition = alltrue([
      for p in values(var.node_pools) :
      contains(["BALANCED", "ANY"], p.location_policy) &&
      contains(["SURGE", "BLUE_GREEN"], p.upgrade_strategy) &&
      alltrue([for t in p.taints : contains(["NO_SCHEDULE", "PREFER_NO_SCHEDULE", "NO_EXECUTE"], t.effect)])
    ])
    error_message = "Node pool location_policy must be BALANCED or ANY, upgrade_strategy must be SURGE or BLUE_GREEN, and taint effects must be NO_SCHEDULE, PREFER_NO_SCHEDULE, or NO_EXECUTE."
  }
}
