variable "project_id" {
  type        = string
  description = "GCP project ID that hosts both the cluster and the existing VPC."

  validation {
    condition = (
      can(regex("^[a-z][a-z0-9-]*$", var.project_id)) &&
      length(var.project_id) >= 6 &&
      length(var.project_id) <= 30 &&
      !endswith(var.project_id, "-")
    )
    error_message = "project_id must be a valid GCP project ID (6-30 lowercase letters, digits, and hyphens)."
  }
}

variable "vpc_name" {
  type        = string
  description = "Name of the existing VPC. The GKE subnet is expected to be named <vpc_name>-gke-<region> with secondary ranges 'pods' and 'services'."

  validation {
    condition = (
      can(regex("^[a-z][a-z0-9-]*$", var.vpc_name)) &&
      length(var.vpc_name) <= 63
    )
    error_message = "vpc_name must be a valid GCP VPC name (lowercase letters, digits, and hyphens, starting with a letter)."
  }
}

variable "region" {
  type        = string
  description = "GCP region for the regional GKE cluster. A subnet named <vpc_name>-gke-<region> must already exist in this region."
}

variable "cluster_name" {
  type        = string
  description = "Name of the GKE cluster. Must be unique within the project."

  validation {
    condition = (
      can(regex("^[a-z]([-a-z0-9]*[a-z0-9])?$", var.cluster_name)) &&
      length(var.cluster_name) <= 40
    )
    error_message = "cluster_name must start with a lowercase letter and contain only lowercase letters, digits, and hyphens (max 40 characters)."
  }
}

variable "cluster_description" {
  type        = string
  description = "Optional human-readable description of the cluster."
  default     = null
}

variable "release_channel" {
  type        = string
  description = "GKE release channel. STABLE is the recommended production default."
  default     = "STABLE"

  validation {
    condition     = contains(["UNSPECIFIED", "RAPID", "REGULAR", "STABLE"], var.release_channel)
    error_message = "release_channel must be one of UNSPECIFIED, RAPID, REGULAR, or STABLE."
  }
}

variable "kubernetes_version" {
  type        = string
  description = "Optional Kubernetes version override. Defaults to the latest version available in the selected release channel."
  default     = null
}

variable "master_ipv4_cidr_block" {
  type        = string
  description = "CIDR block for the GKE control plane private endpoint. Must be a /28 and must not overlap node or service ranges."
  default     = "172.16.0.0/28"
}

variable "enable_private_nodes" {
  type        = bool
  description = "Whether cluster nodes are created with private IP addresses only. Private nodes require Cloud NAT or equivalent egress in the VPC."
  default     = true
}

variable "enable_private_endpoint" {
  type        = bool
  description = "Whether the control plane is reachable only through its private endpoint. Disable this only if you have a good reason, and then supply master_authorized_networks."
  default     = true

  validation {
    condition     = var.enable_private_endpoint == false ? var.enable_private_nodes == true : true
    error_message = "A private control-plane endpoint requires private nodes (enable_private_nodes must be true)."
  }
}

variable "master_authorized_networks" {
  type = list(object({
    display_name = string
    cidr_block   = string
  }))
  description = "Control-plane networks allowed to reach the public endpoint. Required when enable_private_endpoint is false; ignored otherwise."
  default     = []

  validation {
    condition = (
      var.enable_private_endpoint == false ? length(var.master_authorized_networks) > 0 : true
    )
    error_message = "master_authorized_networks must contain at least one entry when enable_private_endpoint is false."
  }
}

variable "network_policy_enabled" {
  type        = bool
  description = "Whether to enable Calico network policy enforcement."
  default     = true
}

variable "enable_workload_identity" {
  type        = bool
  description = "Whether to enable Workload Identity so pods can authenticate to Google Cloud APIs (Pub/Sub, Cloud Storage, Cloud SQL, etc.)."
  default     = true
}

variable "enable_shielded_nodes" {
  type        = bool
  description = "Whether to enable Shielded GKE Nodes."
  default     = true
}

variable "enable_intranode_visibility" {
  type        = bool
  description = "Whether to enable intra-node visibility for pod-to-pod traffic."
  default     = true
}

variable "enable_vertical_pod_autoscaling" {
  type        = bool
  description = "Whether to enable the Vertical Pod Autoscaling (VPA) cluster feature."
  default     = true
}

variable "enable_cost_allocation" {
  type        = bool
  description = "Whether to enable GKE cost allocation labels."
  default     = true
}

variable "enable_managed_prometheus" {
  type        = bool
  description = "Whether to enable Google Cloud Managed Service for Prometheus."
  default     = true
}

variable "logging_components" {
  type        = list(string)
  description = "GKE components that emit logs."
  default     = ["SYSTEM_COMPONENTS", "WORKLOADS"]

  validation {
    condition = alltrue([
      for c in var.logging_components : contains(["SYSTEM_COMPONENTS", "WORKLOADS"], c)
    ])
    error_message = "logging_components supports only SYSTEM_COMPONENTS and WORKLOADS."
  }
}

variable "monitoring_components" {
  type        = list(string)
  description = "GKE system components that emit metrics."
  default     = ["SYSTEM_COMPONENTS", "APISERVER", "SCHEDULER", "CONTROLLER_MANAGER"]

  validation {
    condition = alltrue([
      for c in var.monitoring_components : contains(["SYSTEM_COMPONENTS", "APISERVER", "SCHEDULER", "CONTROLLER_MANAGER"], c)
    ])
    error_message = "monitoring_components supports only SYSTEM_COMPONENTS, APISERVER, SCHEDULER, and CONTROLLER_MANAGER."
  }
}

variable "maintenance_start_time" {
  type        = string
  description = "Start time (RFC 3339 timestamp) of the recurring maintenance window. Recurrence scheduling is relative to this timestamp's date."
  default     = "2025-01-01T03:00:00Z"
}

variable "maintenance_end_time" {
  type        = string
  description = "End time (RFC 3339 timestamp) of the recurring maintenance window."
  default     = "2025-01-01T07:00:00Z"
}

variable "maintenance_recurrence" {
  type        = string
  description = "RFC 5545 RRULE for the recurring maintenance window."
  default     = "FREQ=WEEKLY;BYDAY=SA,SU"
}

variable "deletion_protection" {
  type        = bool
  description = "Whether to prevent the cluster from being deleted accidentally."
  default     = true
}

variable "node_pools" {
  type = map(object({
    machine_type       = string
    min_node_count     = number
    max_node_count     = number
    disk_size_gb       = optional(number, 100)
    disk_type          = optional(string, "pd-ssd")
    image_type         = optional(string, "COS_CONTAINERD")
    auto_repair        = optional(bool, true)
    auto_upgrade       = optional(bool, true)
    enable_secure_boot = optional(bool, true)
    labels             = optional(map(string), {})
    service_account    = optional(string, "")
    taints = optional(list(object({
      key    = string
      value  = string
      effect = string
    })), [])
  }))
  description = "Map of managed node pools. Defaults provide a general-purpose production pool; add or override pools as needed."

  default = {
    general = {
      machine_type   = "e2-standard-4"
      min_node_count = 1
      max_node_count = 8
    }
  }

  validation {
    condition = alltrue([
      for name, pool in var.node_pools :
      can(regex("^[a-z]([-a-z0-9]*[a-z0-9])?$", name)) && length(name) <= 40 && name != "default"
    ])
    error_message = "Node pool names must be valid GKE node pool names (lowercase letters, digits, hyphens), must not be 'default', and must be at most 40 characters."
  }

  validation {
    condition = alltrue([
      for name, pool in var.node_pools :
      pool.min_node_count >= 0 &&
      pool.min_node_count <= pool.max_node_count
    ])
    error_message = "Every node pool must have min_node_count >= 0 and min_node_count <= max_node_count."
  }

  validation {
    condition = alltrue([
      for name, pool in var.node_pools :
      alltrue([
        for taint in pool.taints : contains(["NO_SCHEDULE", "PREFER_NO_SCHEDULE", "NO_EXECUTE"], taint.effect)
      ])
    ])
    error_message = "Node pool taint effect must be one of NO_SCHEDULE, PREFER_NO_SCHEDULE, or NO_EXECUTE."
  }
}