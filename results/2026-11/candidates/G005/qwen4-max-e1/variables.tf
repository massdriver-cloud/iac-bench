# ---------------------------------------------------------------------------
# Required, cluster-specific inputs. Everything else has a production-ready
# default chosen by the platform team.
# ---------------------------------------------------------------------------

variable "project_id" {
  description = "Google Cloud project that owns the environment VPC. The cluster is created in this same project."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "project_id must be a valid Google Cloud project ID."
  }
}

variable "cluster_name" {
  description = "Name of the GKE cluster. Also used as a prefix for the node service account and node pool, so keep it short (<= 24 chars)."
  type        = string

  validation {
    condition     = can(regex("^[a-z]([-a-z0-9]{0,22}[a-z0-9])?$", var.cluster_name))
    error_message = "cluster_name must be 1-24 characters, lowercase letters/digits/hyphens, start with a letter and end with a letter or digit."
  }
}

variable "environment" {
  description = "Environment whose network this cluster joins. Selects the VPC 'apps-<environment>' and subnet 'apps-<environment>-gke-<region>'."
  type        = string

  validation {
    condition     = contains(["staging", "prod"], var.environment)
    error_message = "environment must be \"staging\" or \"prod\" (the network team owns apps-staging and apps-prod)."
  }
}

variable "master_ipv4_cidr_block" {
  description = "A /28 RFC1918 range for the private control-plane endpoint. Must not overlap any range in the VPC and must be UNIQUE per cluster in the same VPC (e.g. 172.16.0.0/28, 172.16.0.16/28, ...)."
  type        = string

  validation {
    condition     = can(cidrnetmask(var.master_ipv4_cidr_block)) && tonumber(split("/", var.master_ipv4_cidr_block)[1]) == 28
    error_message = "master_ipv4_cidr_block must be a valid CIDR with a /28 prefix length."
  }
}

variable "master_authorized_networks" {
  description = "CIDR blocks allowed to reach the Kubernetes API server (e.g. office/VPN egress ranges). Required: the API endpoint is never left open to the internet. Pass an empty list only when enable_private_endpoint is true."
  type = list(object({
    cidr_block   = string
    display_name = string
  }))

  validation {
    condition     = alltrue([for n in var.master_authorized_networks : can(cidrnetmask(n.cidr_block))])
    error_message = "Every master_authorized_networks entry must have a valid CIDR block."
  }
}

# ---------------------------------------------------------------------------
# Optional inputs with safe production defaults.
# ---------------------------------------------------------------------------

variable "region" {
  description = "US region for this regional cluster. Nodes are spread across all zones in the region; the GKE subnet 'apps-<environment>-gke-<region>' must already exist."
  type        = string
  default     = "us-central1"

  validation {
    condition     = can(regex("^us-(central1|east1|east4|east5|west1|west2|west3|west4|south1)$", var.region))
    error_message = "region must be a US region (us-*)."
  }
}

variable "node_locations" {
  description = "Explicit zones for the node pool. Leave null to use every zone in the region (recommended for resilience)."
  type        = list(string)
  default     = null
}

variable "release_channel" {
  description = "GKE release channel. REGULAR gives tested upgrades on a predictable cadence; use STABLE for the most conservative rollout."
  type        = string
  default     = "REGULAR"

  validation {
    condition     = contains(["RAPID", "REGULAR", "STABLE"], var.release_channel)
    error_message = "release_channel must be RAPID, REGULAR or STABLE."
  }
}

variable "machine_type" {
  description = "Machine type for worker nodes. Shared multi-team production clusters need headroom; size up rather than down."
  type        = string
  default     = "e2-standard-4"
}

variable "min_nodes_per_zone" {
  description = "Autoscaler minimum node count PER ZONE. With the default of 1 and a 3-zone region the cluster never runs fewer than 3 nodes."
  type        = number
  default     = 1

  validation {
    condition     = var.min_nodes_per_zone >= 1
    error_message = "min_nodes_per_zone must be at least 1 so every zone keeps capacity."
  }
}

variable "max_nodes_per_zone" {
  description = "Autoscaler maximum node count PER ZONE."
  type        = number
  default     = 3

  validation {
    condition     = var.max_nodes_per_zone >= 1
    error_message = "max_nodes_per_zone must be at least 1."
  }
}

variable "disk_size_gb" {
  description = "Boot disk size (GB) per node."
  type        = number
  default     = 100

  validation {
    condition     = var.disk_size_gb >= 50
    error_message = "disk_size_gb must be at least 50 GB for production nodes."
  }
}

variable "disk_type" {
  description = "Boot disk type for nodes."
  type        = string
  default     = "pd-balanced"

  validation {
    condition     = contains(["pd-balanced", "pd-ssd", "pd-standard"], var.disk_type)
    error_message = "disk_type must be pd-balanced, pd-ssd or pd-standard."
  }
}

variable "max_pods_per_node" {
  description = "Maximum pods per node. 64 keeps pod IP consumption per node predictable against the network team's 'pods' secondary range."
  type        = number
  default     = 64

  validation {
    condition     = var.max_pods_per_node >= 16 && var.max_pods_per_node <= 110
    error_message = "max_pods_per_node must be between 16 and 110."
  }
}

variable "enable_private_endpoint" {
  description = "When true the API server has no public IP at all and is only reachable from inside the VPC (VPN/interconnect/bastion required). Nodes are always private either way."
  type        = bool
  default     = false
}

variable "deletion_protection" {
  description = "Protect the cluster from accidental destruction. Must be explicitly set to false (and applied) before the cluster can be destroyed."
  type        = bool
  default     = true
}

variable "maintenance_start_time" {
  description = "Daily maintenance window start time (UTC, HH:MM). GKE performs node/control-plane maintenance inside this window."
  type        = string
  default     = "04:00"

  validation {
    condition     = can(regex("^([01][0-9]|2[0-3]):[0-5][0-9]$", var.maintenance_start_time))
    error_message = "maintenance_start_time must be HH:MM in 24-hour UTC."
  }
}

variable "maintenance_exclusions" {
  description = "Optional freeze windows (e.g. peak sales periods) during which no upgrades occur. Times are RFC3339 UTC."
  type = list(object({
    name       = string
    start_time = string
    end_time   = string
  }))
  default = []
}

variable "resource_labels" {
  description = "Extra labels applied to the cluster (cost allocation, ownership, etc.). 'environment' and 'managed-by' are always set by the module."
  type        = map(string)
  default     = {}
}

variable "node_labels" {
  description = "Extra Kubernetes labels applied to every node."
  type        = map(string)
  default     = {}
}
