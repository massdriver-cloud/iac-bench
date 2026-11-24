variable "project_id" {
  description = "Existing Google Cloud project containing the environment VPC and cluster."
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "Use a valid Google Cloud project ID."
  }
}

variable "cluster_name" {
  description = "Unique cluster name within the project (also used for the node service account)."
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,22}[a-z0-9]$", var.cluster_name))
    error_message = "Use 2-24 lowercase letters, digits or hyphens, starting with a letter and ending with a letter or digit."
  }
}

variable "environment" {
  description = "Selects the existing apps-staging or apps-prod VPC."
  type        = string
  validation {
    condition     = contains(["staging", "prod"], var.environment)
    error_message = "Environment must be staging or prod."
  }
}

variable "region" {
  description = "US region containing the existing <vpc>-gke-<region> subnet. GKE chooses three zones in this region."
  type        = string
  validation {
    condition     = can(regex("^us-[a-z]+[0-9]+$", var.region))
    error_message = "Choose a US region, for example us-central1."
  }
}

variable "control_plane_cidr" {
  description = "Dedicated RFC1918 IPv4 /28 for the private control plane. Must not overlap VPC, secondary, peered, VPN or other control-plane ranges. Coordinate allocation with networking."
  type        = string
  validation {
    condition = can(cidrnetmask(var.control_plane_cidr)) && can(regex("/28$", var.control_plane_cidr)) && (
      can(regex("^10\\.", var.control_plane_cidr)) ||
      can(regex("^192\\.168\\.", var.control_plane_cidr)) ||
      can(regex("^172\\.(1[6-9]|2[0-9]|3[01])\\.", var.control_plane_cidr))
    )
    error_message = "Control plane CIDR must be an RFC1918 IPv4 /28."
  }
}

variable "node_machine_type" {
  description = "General-purpose node machine type; size for workload requests and system overhead."
  type        = string
  default     = "e2-standard-4"
}

variable "min_nodes" {
  description = "Minimum total nodes across the three zones (not per zone). At least three for production redundancy."
  type        = number
  default     = 3
  validation {
    condition     = var.min_nodes >= 3 && floor(var.min_nodes) == var.min_nodes
    error_message = "min_nodes must be an integer of at least three."
  }
}

variable "max_nodes" {
  description = "Maximum total nodes across all zones. Budget IP space, quota and surge headroom accordingly."
  type        = number
  default     = 9
  validation {
    condition     = var.max_nodes >= var.min_nodes && floor(var.max_nodes) == var.max_nodes
    error_message = "max_nodes must be an integer greater than or equal to min_nodes."
  }
}

variable "deletion_protection" {
  description = "Protect against accidental cluster deletion. Apply with false before intentional destruction."
  type        = bool
  default     = true
}

variable "maintenance_start_time" {
  description = "RFC3339 start of daily maintenance window (UTC). Defaults to 05:00-09:00 UTC every day. End must be at least four hours later."
  type        = string
  default     = "2025-01-01T05:00:00Z"
}

variable "maintenance_end_time" {
  description = "RFC3339 end of the daily maintenance window. Daily windows must permit at least four contiguous hours."
  type        = string
  default     = "2025-01-01T09:00:00Z"
  validation {
    condition     = try(timecmp(var.maintenance_end_time, timeadd(var.maintenance_start_time, "4h")) >= 0, false)
    error_message = "Maintenance end must be at least four hours after the RFC3339 start."
  }
}

variable "labels" {
  description = "Additional GCP resource labels. Reserved environment and managed_by labels are set by the module."
  type        = map(string)
  default     = {}
}
