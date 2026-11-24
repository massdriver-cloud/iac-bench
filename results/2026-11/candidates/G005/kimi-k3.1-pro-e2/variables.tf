variable "project_id" {
  description = "Google Cloud project containing both the cluster and the environment VPC."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "project_id must be a valid Google Cloud project ID (6-30 characters)."
  }
}

variable "cluster_name" {
  description = "Name of the GKE cluster. It must be unique within the project and region."
  type        = string

  validation {
    condition     = can(regex("^[a-z](?:[-a-z0-9]{0,38}[a-z0-9])?$", var.cluster_name))
    error_message = "cluster_name must be 1-40 characters, start with a lowercase letter, end with a letter or digit, and contain only lowercase letters, digits, and hyphens."
  }
}

variable "region" {
  description = "US region for the regional cluster (for example, us-central1). A region, rather than a zone, is required."
  type        = string

  validation {
    condition     = can(regex("^us-[a-z]+[0-9]+$", var.region))
    error_message = "region must be a US multi-zone region such as us-central1, us-east4, or us-west1, not a zone."
  }
}

variable "environment" {
  description = "Environment whose network will be used. This selects the apps-staging or apps-prod VPC."
  type        = string

  validation {
    condition     = contains(["staging", "prod"], var.environment)
    error_message = "environment must be either staging or prod."
  }
}

variable "master_ipv4_cidr_block" {
  description = "Unique, unused /28 RFC 1918 range for the private GKE control plane. It must not overlap any routed network range."
  type        = string

  validation {
    condition = (
      can(cidrhost(var.master_ipv4_cidr_block, 0)) &&
      try(split("/", var.master_ipv4_cidr_block)[1] == "28", false)
    )
    error_message = "master_ipv4_cidr_block must be a valid /28 CIDR, for example 172.16.0.0/28."
  }
}

variable "labels" {
  description = "Additional resource labels for the cluster and its nodes. Environment and managed-by labels are always supplied by the module."
  type        = map(string)
  default     = {}
}

variable "release_channel" {
  description = "GKE release channel. STABLE is the conservative production default; REGULAR is also supported."
  type        = string
  default     = "STABLE"

  validation {
    condition     = contains(["STABLE", "REGULAR"], var.release_channel)
    error_message = "release_channel must be STABLE or REGULAR. RAPID and unmanaged versions are intentionally not supported for production clusters."
  }
}

variable "maintenance_start_time" {
  description = "UTC start time (HH:MM) for the daily four-hour GKE maintenance window."
  type        = string
  default     = "03:00"

  validation {
    condition     = can(regex("^([01][0-9]|2[0-3]):[0-5][0-9]$", var.maintenance_start_time))
    error_message = "maintenance_start_time must be a UTC time in 24-hour HH:MM format."
  }
}

variable "enable_private_endpoint" {
  description = "Restrict the control plane to its private endpoint. If disabled, at least one master authorized network is required."
  type        = bool
  default     = true
}

variable "master_global_access_enabled" {
  description = "Allow private control-plane access from other Google Cloud regions. Leave disabled unless cross-region private access is required."
  type        = bool
  default     = false
}

variable "master_authorized_networks" {
  description = "Additional CIDRs allowed to reach the control plane. Required when the public control-plane endpoint is enabled."
  type = list(object({
    cidr_block   = string
    display_name = string
  }))
  default = []

  validation {
    condition     = alltrue([for network in var.master_authorized_networks : can(cidrhost(network.cidr_block, 0))])
    error_message = "Every master_authorized_networks entry must contain a valid CIDR block."
  }
}

variable "gke_security_group" {
  description = "Optional Google group (group@example.com) for Kubernetes RBAC with Google Groups. The group must be named gke-security-groups@<domain> or be in that group as required by GKE."
  type        = string
  default     = null
}

variable "upgrade_notification_topic" {
  description = "Optional full Pub/Sub topic ID for GKE upgrade and security notifications, in the form projects/PROJECT/topics/TOPIC."
  type        = string
  default     = null

  validation {
    condition = (
      var.upgrade_notification_topic == null ||
      can(regex("^projects/[a-z][a-z0-9-]{4,28}[a-z0-9]/topics/.+$", var.upgrade_notification_topic))
    )
    error_message = "upgrade_notification_topic must be null or a full Pub/Sub topic ID: projects/PROJECT/topics/TOPIC."
  }
}

variable "logging_components" {
  description = "GKE logging components to collect. The default includes system and application workload logs."
  type        = set(string)
  default     = ["SYSTEM_COMPONENTS", "WORKLOADS"]

  validation {
    condition = alltrue([
      for component in var.logging_components :
      contains(["SYSTEM_COMPONENTS", "WORKLOADS", "APISERVER", "CONTROLLER_MANAGER", "SCHEDULER"], component)
    ])
    error_message = "logging_components contains an unsupported GKE logging component."
  }
}

variable "managed_prometheus_enabled" {
  description = "Enable Google Cloud Managed Service for Prometheus collection for the cluster."
  type        = bool
  default     = true
}

variable "node_service_account_id" {
  description = "Optional explicit account ID for the minimally privileged node service account. Normally the module generates a collision-resistant ID from the cluster name."
  type        = string
  default     = null

  validation {
    condition = (
      var.node_service_account_id == null ||
      can(regex("^[a-z](?:[-a-z0-9]{4,28}[a-z0-9])$", var.node_service_account_id))
    )
    error_message = "node_service_account_id must be 6-30 characters and use the Google service account ID format."
  }
}

variable "node_pools" {
  description = <<-EOT
    Separately managed node pools. The map key is the node pool name. For a regional
    cluster, min_nodes and max_nodes apply per zone. The default general pool keeps
    at least one node in each zone and scales out without scale-in to zero.
  EOT
  type = map(object({
    machine_type      = optional(string, "e2-standard-4")
    min_nodes         = optional(number, 1)
    max_nodes         = optional(number, 6)
    disk_size_gb      = optional(number, 100)
    disk_type         = optional(string, "pd-balanced")
    spot              = optional(bool, false)
    max_pods_per_node = optional(number, 110)
    node_locations    = optional(list(string), [])
    labels            = optional(map(string), {})
    network_tags      = optional(list(string), [])
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
    condition     = length(var.node_pools) > 0
    error_message = "At least one node pool is required."
  }

  validation {
    condition = alltrue([
      for name in keys(var.node_pools) :
      can(regex("^[a-z](?:[-a-z0-9]{0,38}[a-z0-9])?$", name))
    ])
    error_message = "Node pool names must be 1-40 characters, start with a lowercase letter, end with a letter or digit, and contain only lowercase letters, digits, and hyphens."
  }

  validation {
    condition = alltrue([
      for pool in values(var.node_pools) :
      pool.min_nodes >= 0 && pool.max_nodes >= 1 && pool.min_nodes <= pool.max_nodes
    ])
    error_message = "For every node pool, min_nodes must be non-negative, max_nodes must be at least one, and min_nodes cannot exceed max_nodes."
  }

  validation {
    condition = alltrue([
      for pool in values(var.node_pools) :
      pool.disk_size_gb >= 20 && pool.max_pods_per_node >= 8 && pool.max_pods_per_node <= 110
    ])
    error_message = "Node disks must be at least 20 GB and max_pods_per_node must be between 8 and 110."
  }

  validation {
    condition = alltrue(flatten([
      for pool in values(var.node_pools) : [
        for taint in pool.taints :
        contains(["NO_SCHEDULE", "PREFER_NO_SCHEDULE", "NO_EXECUTE"], taint.effect)
      ]
    ]))
    error_message = "Node taint effects must be NO_SCHEDULE, PREFER_NO_SCHEDULE, or NO_EXECUTE."
  }
}

variable "workload_service_accounts" {
  description = <<-EOT
    Optional Google service accounts for product workloads. Each map key is the
    Google service account ID. Each entry binds one Kubernetes namespace/service
    account using Workload Identity and can grant explicit project-level roles,
    such as roles/pubsub.publisher or roles/storage.objectAdmin. Prefer granting
    resource-scoped roles separately when practical.
  EOT
  type = map(object({
    kubernetes_namespace       = string
    kubernetes_service_account = string
    display_name               = optional(string)
    project_roles              = optional(set(string), [])
  }))
  default = {}

  validation {
    condition = alltrue([
      for id in keys(var.workload_service_accounts) :
      can(regex("^[a-z](?:[-a-z0-9]{4,28}[a-z0-9])$", id))
    ])
    error_message = "Every workload_service_accounts key must be a 6-30 character Google service account ID."
  }

  validation {
    condition = alltrue([
      for account in values(var.workload_service_accounts) :
      length(account.kubernetes_namespace) > 0 && length(account.kubernetes_service_account) > 0
    ])
    error_message = "Kubernetes namespace and service account names must not be empty."
  }
}

variable "deletion_protection" {
  description = "Prevent accidental cluster deletion. Keep enabled for production; it must be explicitly disabled before destroying the cluster."
  type        = bool
  default     = true
}

variable "enable_apis" {
  description = "Enable the Google APIs required by this module. Disable only if a central platform pipeline has already enabled them."
  type        = bool
  default     = true
}
