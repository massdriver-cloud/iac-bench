variable "project_id" {
  description = "ID of the Google Cloud project containing the cluster and the environment VPC."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,61}[a-z0-9]$", var.project_id))
    error_message = "project_id must be a valid Google Cloud project ID."
  }
}

variable "cluster_name" {
  description = "Name of the GKE cluster. It must be unique within the project and region."
  type        = string

  validation {
    condition     = can(regex("^[a-z]([-a-z0-9]{0,38}[a-z0-9])?$", var.cluster_name))
    error_message = "cluster_name must start with a letter, contain only lowercase letters, digits, and hyphens, and be at most 40 characters."
  }
}

variable "environment" {
  description = "Environment whose network will be used. This selects the existing apps-staging or apps-prod VPC."
  type        = string

  validation {
    condition     = contains(["staging", "prod"], var.environment)
    error_message = "environment must be either staging or prod."
  }
}

variable "region" {
  description = "US region for the regional cluster, for example us-central1. A regional control plane and nodes in multiple zones are used."
  type        = string

  validation {
    condition     = can(regex("^us-[a-z]+[0-9]+$", var.region))
    error_message = "region must be a US Google Cloud region such as us-central1, us-east1, or us-west1."
  }
}

variable "master_ipv4_cidr_block" {
  description = "Non-overlapping RFC1918 /28 range for the private GKE control plane endpoint. Allocate a different range to every cluster."
  type        = string

  validation {
    condition = try(
      cidrnetmask(var.master_ipv4_cidr_block) != "" && tonumber(split("/", var.master_ipv4_cidr_block)[1]) == 28,
      false
    )
    error_message = "master_ipv4_cidr_block must be a valid /28 CIDR range."
  }
}

variable "enable_private_endpoint" {
  description = "Disable the public control plane endpoint. Keep true unless there is a specifically approved operational requirement; when false, at least one master authorized network is required."
  type        = bool
  default     = true
}

variable "master_global_access_enabled" {
  description = "Allow the private control plane endpoint to be reached through Google Cloud global routing. Leave false when access is only required from the cluster region."
  type        = bool
  default     = false
}

variable "master_authorized_networks" {
  description = "CIDRs allowed to reach the control plane. Required if the public endpoint is enabled; optional as an additional restriction for a private endpoint."
  type = list(object({
    display_name = string
    cidr_block   = string
  }))
  default = []

  validation {
    condition     = alltrue([for network in var.master_authorized_networks : can(cidrnetmask(network.cidr_block))])
    error_message = "Every master authorized network must contain a valid CIDR block."
  }
}

variable "node_locations" {
  description = "Optional zones in region for all node pools. The default null lets GKE select the region's default zones (normally three). If set, specify at least two zones."
  type        = list(string)
  default     = null

  validation {
    condition     = var.node_locations == null || length(var.node_locations) >= 2
    error_message = "node_locations must be null or contain at least two zones for zonal resilience."
  }
}

variable "release_channel" {
  description = "GKE release channel used for automatic control plane and node upgrades."
  type        = string
  default     = "REGULAR"

  validation {
    condition     = contains(["RAPID", "REGULAR", "STABLE"], var.release_channel)
    error_message = "release_channel must be RAPID, REGULAR, or STABLE."
  }
}

variable "maintenance_window" {
  description = "Recurring UTC maintenance window. The default permits disruptive maintenance every day from 07:00 to 11:00 UTC."
  type = object({
    start_time = string
    end_time   = string
    recurrence = string
  })
  default = {
    start_time = "2025-01-01T07:00:00Z"
    end_time   = "2025-01-01T11:00:00Z"
    recurrence = "FREQ=DAILY"
  }
}

variable "notification_pubsub_topic" {
  description = "Optional fully qualified Pub/Sub topic (projects/PROJECT/topics/TOPIC) for GKE upgrade notifications. The topic and permission for the GKE service agent to publish must already exist."
  type        = string
  default     = null

  validation {
    condition     = var.notification_pubsub_topic == null || can(regex("^projects/[^/]+/topics/[^/]+$", var.notification_pubsub_topic))
    error_message = "notification_pubsub_topic must be null or a fully qualified projects/PROJECT/topics/TOPIC name."
  }
}

variable "authenticator_security_group" {
  description = "Optional Google Workspace security group in gke-security-groups@example.com form for Google Groups-based Kubernetes RBAC."
  type        = string
  default     = null
}

variable "labels" {
  description = "Additional resource labels for the cluster. environment and managed-by are always set by the module."
  type        = map(string)
  default     = {}
}

variable "deletion_protection" {
  description = "Protect the cluster against accidental deletion. To destroy intentionally, set false and apply before running destroy."
  type        = bool
  default     = true
}

variable "enable_required_apis" {
  description = "Enable the Google APIs needed by the cluster. Leave true unless APIs are managed centrally; APIs are never disabled when the module is destroyed."
  type        = bool
  default     = true
}

variable "system_node_pool" {
  description = "Sizing for the dedicated, tainted system node pool. Counts are per zone; auto repair, auto upgrade, and surge upgrades are always enabled."
  type = object({
    machine_type      = optional(string, "e2-standard-2")
    disk_size_gb      = optional(number, 100)
    disk_type         = optional(string, "pd-balanced")
    min_node_count    = optional(number, 1)
    max_node_count    = optional(number, 3)
    node_count        = optional(number, 1)
    max_pods_per_node = optional(number, 64)
  })
  default = {}

  validation {
    condition = (
      var.system_node_pool.min_node_count >= 1 &&
      var.system_node_pool.max_node_count >= var.system_node_pool.min_node_count &&
      var.system_node_pool.node_count >= var.system_node_pool.min_node_count &&
      var.system_node_pool.node_count <= var.system_node_pool.max_node_count &&
      var.system_node_pool.disk_size_gb >= 50 &&
      var.system_node_pool.max_pods_per_node >= 8 &&
      var.system_node_pool.max_pods_per_node <= 110
    )
    error_message = "The system pool needs at least one node per zone, consistent min/max/initial counts, at least a 50 GB disk, and 8-110 pods per node."
  }
}

variable "application_node_pools" {
  description = "Application node pools keyed by node pool name. Counts are per zone. The default general pool starts with one node per zone and autoscales; specialized pools may use labels, taints, Spot VMs, or scale to zero."
  type = map(object({
    machine_type      = optional(string, "e2-standard-4")
    disk_size_gb      = optional(number, 100)
    disk_type         = optional(string, "pd-balanced")
    min_node_count    = optional(number, 1)
    max_node_count    = optional(number, 6)
    node_count        = optional(number, 1)
    max_pods_per_node = optional(number, 64)
    labels            = optional(map(string), {})
    taints = optional(list(object({
      key    = string
      value  = string
      effect = string
    })), [])
    spot = optional(bool, false)
  }))
  default = {
    general = {}
  }

  validation {
    condition = alltrue([
      for name, pool in var.application_node_pools :
      can(regex("^[a-z]([-a-z0-9]{0,28}[a-z0-9])?$", name)) && name != "system"
    ])
    error_message = "Application pool names must be valid names of at most 30 characters, and system is reserved."
  }

  validation {
    condition = alltrue([
      for pool in values(var.application_node_pools) :
      pool.min_node_count >= 0 &&
      pool.max_node_count >= 1 &&
      pool.max_node_count >= pool.min_node_count &&
      pool.node_count >= pool.min_node_count &&
      pool.node_count <= pool.max_node_count &&
      pool.disk_size_gb >= 50 &&
      pool.max_pods_per_node >= 8 &&
      pool.max_pods_per_node <= 110
    ])
    error_message = "Application pools need consistent min/max/initial counts, at least a 50 GB disk, and 8-110 pods per node."
  }

  validation {
    condition = alltrue([
      for pool in values(var.application_node_pools) :
      alltrue([for taint in pool.taints : contains(["NO_SCHEDULE", "PREFER_NO_SCHEDULE", "NO_EXECUTE"], taint.effect)])
    ])
    error_message = "Node taint effects must be NO_SCHEDULE, PREFER_NO_SCHEDULE, or NO_EXECUTE."
  }
}

variable "workload_identity_bindings" {
  description = "Existing Google service accounts to bind to Kubernetes service accounts. Keys are stable Terraform addresses. Application-specific Pub/Sub, Storage, and SQL roles are granted separately to the Google service account, never to the node identity."
  type = map(object({
    namespace                    = string
    kubernetes_service_account   = string
    google_service_account_email = string
  }))
  default = {}

  validation {
    condition = alltrue([
      for binding in values(var.workload_identity_bindings) :
      can(regex("^[^@]+@[^@]+\\.iam\\.gserviceaccount\\.com$", binding.google_service_account_email)) &&
      can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", binding.namespace)) &&
      can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", binding.kubernetes_service_account))
    ])
    error_message = "Each Workload Identity binding needs valid Kubernetes namespace/service account names and a Google service account email."
  }
}
