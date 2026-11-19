variable "project_id" {
  description = "Project the cluster and its networks live in."
  type        = string
}

variable "name" {
  description = "Cluster name, unique within the project and region."
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,38}[a-z0-9]$", var.name))
    error_message = "Use 2-40 lowercase letters, digits and hyphens, starting with a letter."
  }
}

variable "environment" {
  description = "Environment whose network the cluster joins: staging or prod."
  type        = string
  validation {
    condition     = contains(["staging", "prod"], var.environment)
    error_message = "environment must be staging or prod."
  }
}

variable "region" {
  description = "Region for the regional cluster; its GKE subnet must already exist."
  type        = string
}

variable "node_pools" {
  description = "Node pools keyed by name. Each autoscales between min_nodes and max_nodes per zone."
  type = map(object({
    machine_type = optional(string, "e2-standard-4")
    min_nodes    = optional(number, 1)
    max_nodes    = optional(number, 5)
    disk_size_gb = optional(number, 100)
    spot         = optional(bool, false)
    labels       = optional(map(string), {})
    taints = optional(list(object({
      key    = string
      value  = string
      effect = string
    })), [])
  }))
  default = { general = {} }
}

variable "authorized_networks" {
  description = "CIDR blocks allowed to reach the control plane's IP endpoint, keyed by display name. Empty allows only Google Cloud internal addresses and the DNS endpoint."
  type        = map(string)
  default     = {}
}

variable "maintenance_window" {
  description = "Recurring window in which GKE may upgrade the cluster (RFC 3339 start and end, RFC 5545 recurrence)."
  type = object({
    start_time = string
    end_time   = string
    recurrence = string
  })
  default = {
    start_time = "2026-01-01T09:00:00Z"
    end_time   = "2026-01-01T13:00:00Z"
    recurrence = "FREQ=WEEKLY;BYDAY=TU,WE,TH"
  }
}

variable "secrets_encryption_key" {
  description = "Cloud KMS key (projects/.../cryptoKeys/...) that encrypts Kubernetes Secrets in etcd. The GKE service agent is granted use of it."
  type        = string
  default     = null
}

variable "rbac_security_group" {
  description = "Google Group (gke-security-groups@<domain>) whose member groups can be bound in Kubernetes RBAC."
  type        = string
  default     = null
}

variable "deletion_protection" {
  description = "Refuse to destroy the cluster. Set false only to retire it."
  type        = bool
  default     = true
}

variable "labels" {
  description = "Labels applied to every resource the module creates."
  type        = map(string)
  default     = {}
}
