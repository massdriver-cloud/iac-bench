variable "project_id" {
  description = "Google Cloud project ID where the VPC and GKE cluster reside."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "project_id must be a valid GCP project ID (6-30 lowercase letters, digits, or hyphens)."
  }
}

variable "cluster_name" {
  description = "Name of the GKE Standard cluster."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,38}[a-z0-9]$", var.cluster_name))
    error_message = "cluster_name must be 2-40 characters, start with a lowercase letter, end with an alphanumeric character, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "environment" {
  description = "Target environment matching the network team's VPC naming ('staging' -> apps-staging, 'prod' -> apps-prod)."
  type        = string

  validation {
    condition     = contains(["staging", "prod"], var.environment)
    error_message = "environment must be either 'staging' or 'prod'."
  }
}

variable "region" {
  description = "US Google Cloud region for the regional GKE cluster and its pre-created subnet (<vpc>-gke-<region>)."
  type        = string

  validation {
    condition     = can(regex("^us-[a-z]+[0-9]+$", var.region))
    error_message = "region must be a valid US Google Cloud region (e.g., us-central1, us-east4)."
  }
}

variable "master_ipv4_cidr_block" {
  description = "Unique /28 CIDR block for the GKE control plane VPC peering in the shared VPC (e.g., 172.16.0.0/28). Must not overlap with other clusters in the same VPC."
  type        = string
  default     = "172.16.0.0/28"

  validation {
    condition     = can(cidrhost(var.master_ipv4_cidr_block, 0)) && endswith(var.master_ipv4_cidr_block, "/28")
    error_message = "master_ipv4_cidr_block must be a valid /28 IPv4 CIDR block."
  }
}

variable "release_channel" {
  description = "GKE release channel for automated control plane and node upgrades (RAPID, REGULAR, or STABLE)."
  type        = string
  default     = "REGULAR"

  validation {
    condition     = contains(["RAPID", "REGULAR", "STABLE"], var.release_channel)
    error_message = "release_channel must be one of RAPID, REGULAR, or STABLE."
  }
}

variable "kubernetes_version" {
  description = "Optional minimum control plane Kubernetes version. Leave null to let the release channel manage versions."
  type        = string
  default     = null
}

variable "deletion_protection" {
  description = "Prevent accidental cluster deletion via Terraform/OpenTofu."
  type        = bool
  default     = true
}

variable "enable_private_endpoint" {
  description = "When true, disables public IP access to the Kubernetes API server; requires VPC-internal access (VPN/Interconnect/bastion)."
  type        = bool
  default     = false
}

variable "enable_master_global_access" {
  description = "Allow access to the private control plane endpoint from any GCP region within the VPC."
  type        = bool
  default     = true
}

variable "master_authorized_networks" {
  description = "List of CIDR blocks allowed to reach the Kubernetes API server endpoint."
  type = list(object({
    cidr_block   = string
    display_name = string
  }))
  default = []
}

variable "create_master_webhook_firewall_rule" {
  description = "Create a VPC firewall rule allowing the GKE control plane to reach admission/conversion webhooks on cluster nodes."
  type        = bool
  default     = true
}

variable "master_webhook_ports" {
  description = "TCP ports opened from master_ipv4_cidr_block to cluster nodes for Kubernetes admission webhooks (e.g., cert-manager, External Secrets, Ingress)."
  type        = list(string)
  default     = ["6443", "8443", "9443"]
}

variable "maintenance_window" {
  description = "Recurring UTC maintenance window for automated GKE upgrades. Defaults to weekends 04:00-10:00 UTC."
  type = object({
    start_time = string
    end_time   = string
    recurrence = string
  })
  default = {
    start_time = "2024-01-01T04:00:00Z"
    end_time   = "2024-01-01T10:00:00Z"
    recurrence = "FREQ=WEEKLY;BYDAY=SA,SU"
  }
}

variable "maintenance_exclusions" {
  description = "Optional maintenance exclusion windows (e.g., release freezes)."
  type = list(object({
    name       = string
    start_time = string
    end_time   = string
    scope      = optional(string, "NO_UPGRADES")
  }))
  default = []
}

variable "node_pools" {
  description = "Map of managed GKE node pools. Defaults to a dedicated 'system' pool for cluster add-ons and a 'general' pool for product workloads."
  type = map(object({
    machine_type       = optional(string, "e2-standard-4")
    disk_size_gb       = optional(number, 100)
    disk_type          = optional(string, "pd-balanced")
    min_nodes_per_zone = optional(number, 1)
    max_nodes_per_zone = optional(number, 10)
    spot               = optional(bool, false)
    max_surge          = optional(number, 1)
    max_unavailable    = optional(number, 0)
    node_locations     = optional(list(string), [])
    labels             = optional(map(string), {})
    taints = optional(list(object({
      key    = string
      value  = string
      effect = string
    })), [])
  }))
  default = {
    system = {
      machine_type       = "e2-standard-2"
      disk_size_gb       = 50
      disk_type          = "pd-balanced"
      min_nodes_per_zone = 1
      max_nodes_per_zone = 3
      labels = {
        "workload-type" = "system"
      }
      taints = [
        {
          key    = "CriticalAddonsOnly"
          value  = "true"
          effect = "NO_SCHEDULE"
        }
      ]
    }
    general = {
      machine_type       = "e2-standard-4"
      disk_size_gb       = 100
      disk_type          = "pd-balanced"
      min_nodes_per_zone = 1
      max_nodes_per_zone = 10
      labels = {
        "workload-type" = "general"
      }
    }
  }

  validation {
    condition = alltrue([
      for k, pool in var.node_pools :
      pool.min_nodes_per_zone >= 0 &&
      pool.max_nodes_per_zone >= pool.min_nodes_per_zone &&
      pool.disk_size_gb >= 30 &&
      contains(["pd-standard", "pd-balanced", "pd-ssd", "hyperdisk-balanced"], pool.disk_type)
    ])
    error_message = "Each node pool must have min_nodes_per_zone >= 0, max_nodes_per_zone >= min_nodes_per_zone, disk_size_gb >= 30, and a valid disk_type."
  }
}

variable "authenticator_security_group" {
  description = "Optional Google Workspace group (e.g., gke-security-groups@example.com) for Kubernetes RBAC."
  type        = string
  default     = null
}

variable "etcd_kms_key_name" {
  description = "Optional Cloud KMS CryptoKey resource ID for customer-managed encryption of Kubernetes secrets in etcd."
  type        = string
  default     = null
}

variable "enable_binary_authorization" {
  description = "Enable Binary Authorization project singleton policy enforcement for container images."
  type        = bool
  default     = false
}

variable "enable_managed_prometheus" {
  description = "Enable Google Cloud Managed Service for Prometheus on the cluster."
  type        = bool
  default     = true
}

variable "enable_gcs_fuse_csi_driver" {
  description = "Enable the Cloud Storage FUSE CSI driver for mounting GCS buckets via Workload Identity."
  type        = bool
  default     = true
}

variable "enable_filestore_csi_driver" {
  description = "Enable the Cloud Filestore CSI driver."
  type        = bool
  default     = false
}

variable "enable_secret_manager_addon" {
  description = "Enable the Secret Manager add-on for consuming GCP Secret Manager secrets in Kubernetes pods."
  type        = bool
  default     = true
}

variable "enable_gke_backup_agent" {
  description = "Enable the Backup for GKE agent add-on for stateful workload backups."
  type        = bool
  default     = true
}

variable "labels" {
  description = "Additional GCP resource labels applied to the cluster and node pools."
  type        = map(string)
  default     = {}
}
