variable "project_id" {
  description = "Google Cloud project ID. The cluster and the existing environment VPC must both be in this project."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,61}[a-z0-9]$", var.project_id))
    error_message = "project_id must be a valid Google Cloud project ID (6-63 lowercase letters, digits, and hyphens)."
  }
}

variable "cluster_name" {
  description = "Name of the GKE cluster. This is also used as a prefix for cluster-owned supporting resources."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-z](?:[a-z0-9-]{0,38}[a-z0-9])?$", var.cluster_name))
    error_message = "cluster_name must be 1-40 characters, start with a letter, and contain only lowercase letters, digits, and hyphens."
  }
}

variable "environment" {
  description = "Environment whose existing VPC will be used. staging selects apps-staging; prod selects apps-prod."
  type        = string
  nullable    = false

  validation {
    condition     = contains(["staging", "prod"], var.environment)
    error_message = "environment must be either staging or prod."
  }
}

variable "region" {
  description = "US region for the regional GKE cluster. The subnet named <vpc>-gke-<region> must already exist in this region."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^us-[a-z]+[0-9]+$", var.region))
    error_message = "region must be a US Google Cloud region, for example us-central1 or us-east4."
  }
}

variable "master_ipv4_cidr_block" {
  description = "Unique, non-overlapping /28 RFC1918 range for the private GKE control plane (for example 172.16.0.0/28). Coordinate this range with the network team."
  type        = string
  nullable    = false

  validation {
    condition     = can(cidrnetmask(var.master_ipv4_cidr_block)) && try(tonumber(split("/", var.master_ipv4_cidr_block)[1]) == 28, false)
    error_message = "master_ipv4_cidr_block must be a valid /28 IPv4 CIDR block."
  }
}

variable "labels" {
  description = "Additional labels for the cluster and cluster-owned supporting resources. Reserved module labels take precedence."
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "node_locations" {
  description = "Optional set of zones in region in which to place nodes. By default GKE uses the region's default zones, normally providing one node instance group per zone."
  type        = set(string)
  default     = []
  nullable    = false
}

variable "deletion_protection" {
  description = "Prevent accidental deletion of the cluster through OpenTofu. Keep true for production; explicitly set false before intentional teardown."
  type        = bool
  default     = true
  nullable    = false
}

variable "release_channel" {
  description = "GKE release channel used for control-plane and node upgrades."
  type        = string
  default     = "REGULAR"
  nullable    = false

  validation {
    condition     = contains(["RAPID", "REGULAR", "STABLE"], var.release_channel)
    error_message = "release_channel must be RAPID, REGULAR, or STABLE."
  }
}

variable "min_master_version" {
  description = "Optional minimum control-plane version. Normally leave null and let the selected release channel manage versions."
  type        = string
  default     = null
}

variable "enable_private_endpoint" {
  description = "Make the control-plane endpoint private. The default true requires kubectl access from a connected private network; if false, configure master_authorized_networks to restrict the public endpoint."
  type        = bool
  default     = true
  nullable    = false
}

variable "enable_master_global_access" {
  description = "Allow access to the private control-plane endpoint from other Google Cloud regions through connected private networks."
  type        = bool
  default     = true
  nullable    = false
}

variable "master_authorized_networks" {
  description = "CIDRs authorized to reach the control-plane endpoint. Particularly important when enable_private_endpoint is false."
  type = list(object({
    cidr_block   = string
    display_name = string
  }))
  default  = []
  nullable = false

  validation {
    condition     = alltrue([for network in var.master_authorized_networks : can(cidrnetmask(network.cidr_block))])
    error_message = "Every master_authorized_networks entry must contain a valid CIDR block."
  }
}

variable "maintenance_start_time" {
  description = "UTC start time for the daily four-hour GKE maintenance window, in 24-hour HH:MM format."
  type        = string
  default     = "03:00"
  nullable    = false

  validation {
    condition     = can(regex("^(?:[01][0-9]|2[0-3]):[0-5][0-9]$", var.maintenance_start_time))
    error_message = "maintenance_start_time must be a UTC time in HH:MM format."
  }
}

variable "rbac_security_group" {
  description = "Optional Google group in gke-security-groups@example.com form for Kubernetes RBAC group membership. Leave null unless Google Groups for RBAC is configured."
  type        = string
  default     = null

  validation {
    condition     = var.rbac_security_group == null || can(regex("^gke-security-groups@[A-Za-z0-9.-]+$", var.rbac_security_group))
    error_message = "rbac_security_group must be a full gke-security-groups@domain group address or null."
  }
}

variable "enable_managed_prometheus" {
  description = "Enable Google Cloud Managed Service for Prometheus for workload metrics collection."
  type        = bool
  default     = true
  nullable    = false
}

variable "enable_binary_authorization" {
  description = "Evaluate deployments against the project's Binary Authorization policy. The platform team should own that project-level policy separately."
  type        = bool
  default     = true
  nullable    = false
}

variable "enable_backup_agent" {
  description = "Install the Backup for GKE agent so application-consistent backup plans can be attached later. Backup plans themselves are intentionally application-specific."
  type        = bool
  default     = true
  nullable    = false
}

variable "additional_node_service_account_roles" {
  description = "Additional project-level roles required by node infrastructure. Do not use this for application permissions; use workload_service_accounts instead."
  type        = set(string)
  default     = []
  nullable    = false
}

variable "node_pools" {
  description = <<-EOT
    Map of separately managed node pools. min_node_count and max_node_count are per zone, not regional totals.
    The default creates dedicated, tainted system and untainted applications pools. A user-supplied map replaces
    the complete default map; omitted object attributes use the documented attribute defaults. Set spot=true only
    for interruption-tolerant pools.
  EOT
  type = map(object({
    machine_type      = optional(string, "e2-standard-4")
    image_type        = optional(string, "COS_CONTAINERD")
    disk_size_gb      = optional(number, 100)
    disk_type         = optional(string, "pd-balanced")
    min_node_count    = optional(number, 1)
    max_node_count    = optional(number, 3)
    location_policy   = optional(string, "BALANCED")
    max_pods_per_node = optional(number, 64)
    spot              = optional(bool, false)
    labels            = optional(map(string), {})
    tags              = optional(set(string), [])
    local_ssd_count   = optional(number, 0)
    taints = optional(list(object({
      key    = string
      value  = string
      effect = string
    })), [])
  }))
  default = {
    system = {
      machine_type   = "e2-standard-2"
      min_node_count = 1
      max_node_count = 3
      labels = {
        workload = "system"
      }
      taints = [{
        key    = "CriticalAddonsOnly"
        value  = "true"
        effect = "NO_SCHEDULE"
      }]
    }
    applications = {
      machine_type   = "e2-standard-4"
      min_node_count = 1
      max_node_count = 6
      labels = {
        workload = "applications"
      }
    }
  }
  nullable = false

  validation {
    condition     = length(var.node_pools) > 0
    error_message = "At least one node pool is required."
  }

  validation {
    condition = alltrue([
      for name, pool in var.node_pools :
      can(regex("^[a-z](?:[a-z0-9-]{0,38}[a-z0-9])?$", name))
    ])
    error_message = "Node-pool map keys become pool names and must be 1-40 lowercase letters, digits, and hyphens, starting with a letter."
  }

  validation {
    condition = alltrue([
      for pool in values(var.node_pools) :
      pool.min_node_count >= 0 && pool.max_node_count > 0 && pool.min_node_count <= pool.max_node_count
    ])
    error_message = "For every node pool, min_node_count must be non-negative, max_node_count must be positive, and min cannot exceed max."
  }

  validation {
    condition = alltrue([
      for pool in values(var.node_pools) :
      pool.disk_size_gb >= 20 && pool.max_pods_per_node >= 8 && pool.max_pods_per_node <= 110 && pool.local_ssd_count >= 0
    ])
    error_message = "Node disks must be at least 20 GB, max_pods_per_node must be 8-110, and local_ssd_count cannot be negative."
  }

  validation {
    condition = alltrue([
      for pool in values(var.node_pools) :
      contains(["BALANCED", "ANY"], pool.location_policy)
    ])
    error_message = "Node-pool location_policy must be BALANCED or ANY."
  }

  validation {
    condition = alltrue(flatten([
      for pool in values(var.node_pools) : [
        for taint in pool.taints : contains(["NO_SCHEDULE", "PREFER_NO_SCHEDULE", "NO_EXECUTE"], taint.effect)
      ]
    ]))
    error_message = "Node-pool taint effects must be NO_SCHEDULE, PREFER_NO_SCHEDULE, or NO_EXECUTE."
  }
}

variable "workload_service_accounts" {
  description = <<-EOT
    Optional map of Google service accounts for applications. Each map key is the Google service-account ID
    (6-30 characters). project_roles should contain only the application's least-privilege roles, such as
    roles/pubsub.publisher, roles/storage.objectAdmin, or roles/cloudsql.client. Each entry in
    kubernetes_service_accounts is a namespace/service-account-name string. The module creates the Google
    service account and IAM bindings; product teams create and annotate the Kubernetes service account.
  EOT
  type = map(object({
    display_name                = optional(string)
    description                 = optional(string)
    project_roles               = optional(set(string), [])
    kubernetes_service_accounts = set(string)
  }))
  default  = {}
  nullable = false

  validation {
    condition = alltrue([
      for account_id in keys(var.workload_service_accounts) :
      can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", account_id))
    ])
    error_message = "Each workload_service_accounts key must be a valid 6-30 character Google service-account ID."
  }

  validation {
    condition = alltrue(flatten([
      for account in values(var.workload_service_accounts) : [
        for identity in account.kubernetes_service_accounts :
        can(regex("^[a-z0-9](?:[-a-z0-9]*[a-z0-9])?/[a-z0-9](?:[-a-z0-9.]*[a-z0-9])?$", identity))
      ]
    ]))
    error_message = "Each Kubernetes workload identity must use the form namespace/service-account-name and valid Kubernetes names."
  }

  validation {
    condition = alltrue([
      for account in values(var.workload_service_accounts) : length(account.kubernetes_service_accounts) > 0
    ])
    error_message = "Every workload Google service account must identify at least one Kubernetes service account."
  }
}
