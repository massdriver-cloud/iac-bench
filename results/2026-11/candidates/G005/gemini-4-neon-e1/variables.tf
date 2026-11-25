# ------------------------------------------------------------------------------
# Required Cluster-Specific Inputs
# ------------------------------------------------------------------------------

variable "project_id" {
  description = "Google Cloud project ID where the cluster and environment VPC live."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "project_id must be a valid Google Cloud project ID (6-30 lowercase letters, digits, or hyphens)."
  }
}

variable "environment" {
  description = "Target environment matching the network team's VPC convention ('staging' -> apps-staging, 'prod' -> apps-prod)."
  type        = string

  validation {
    condition     = contains(["staging", "prod"], var.environment)
    error_message = "environment must be either \"staging\" or \"prod\"."
  }
}

variable "region" {
  description = "US Google Cloud region for the regional cluster. Must match one of the network team's pre-created <vpc>-gke-<region> subnets (e.g., us-central1, us-east1, us-west1)."
  type        = string

  validation {
    condition     = can(regex("^us-[a-z]+[0-9]$", var.region))
    error_message = "region must be a valid US Google Cloud region (e.g., us-central1, us-east1, us-east4, us-west1)."
  }
}

variable "cluster_name" {
  description = "Unique name for this GKE Standard cluster within the project and region."
  type        = string

  validation {
    condition     = can(regex("^[a-z]([a-z0-9-]{0,38}[a-z0-9])?$", var.cluster_name))
    error_message = "cluster_name must be 1-40 characters of lowercase letters, digits, or hyphens, starting with a letter and ending with a letter or digit."
  }
}

variable "control_plane_cidr" {
  description = "Dedicated /28 RFC1918 private IPv4 CIDR block for the GKE control plane (e.g., 172.16.0.0/28). Must be unique per cluster and not overlap with any subnets in the VPC."
  type        = string

  validation {
    condition = (
      can(cidrnetmask(var.control_plane_cidr)) &&
      endswith(var.control_plane_cidr, "/28") &&
      can(regex("^(10\\.|172\\.(1[6-9]|2[0-9]|3[0-1])\\.|192\\.168\\.)", var.control_plane_cidr))
    )
    error_message = "control_plane_cidr must be a valid RFC1918 private /28 IPv4 CIDR block (e.g., 172.16.0.0/28)."
  }
}

# ------------------------------------------------------------------------------
# Cluster Lifecycle & Resilience
# ------------------------------------------------------------------------------

variable "deletion_protection" {
  description = "Prevent accidental deletion of the cluster via OpenTofu or the GKE API. Keep enabled for production clusters."
  type        = bool
  default     = true
}

variable "release_channel" {
  description = "GKE release channel managing automated Kubernetes control plane and node upgrades (STABLE, REGULAR, or RAPID)."
  type        = string
  default     = "REGULAR"

  validation {
    condition     = contains(["STABLE", "REGULAR", "RAPID"], var.release_channel)
    error_message = "release_channel must be one of STABLE, REGULAR, or RAPID."
  }
}

variable "maintenance_window" {
  description = "Recurring maintenance window for automated GKE upgrades. Must provide at least 48 hours of availability in any 32-day rolling window, with each window at least 4 hours long. Defaults to Saturday and Sunday 02:00-10:00 UTC."
  type = object({
    start_time = string
    end_time   = string
    recurrence = string
  })
  default = {
    start_time = "2024-01-06T02:00:00Z"
    end_time   = "2024-01-06T10:00:00Z"
    recurrence = "FREQ=WEEKLY;BYDAY=SA,SU"
  }
}

variable "maintenance_exclusions" {
  description = "Optional temporary freeze windows during which GKE will defer automatic upgrades (e.g., peak traffic events)."
  type = list(object({
    name       = string
    start_time = string
    end_time   = string
    scope      = optional(string, "NO_UPGRADES")
  }))
  default = []

  validation {
    condition = alltrue([
      for e in var.maintenance_exclusions :
      contains(["NO_UPGRADES", "NO_MINOR_UPGRADES", "NO_MINOR_OR_NODE_UPGRADES"], e.scope)
    ])
    error_message = "Each maintenance exclusion scope must be NO_UPGRADES, NO_MINOR_UPGRADES, or NO_MINOR_OR_NODE_UPGRADES."
  }
}

variable "autoscaling_profile" {
  description = "Cluster Autoscaler behavior: BALANCED (default) or OPTIMIZE_UTILIZATION (more aggressive scale-down)."
  type        = string
  default     = "BALANCED"

  validation {
    condition     = contains(["BALANCED", "OPTIMIZE_UTILIZATION"], var.autoscaling_profile)
    error_message = "autoscaling_profile must be BALANCED or OPTIMIZE_UTILIZATION."
  }
}

# ------------------------------------------------------------------------------
# Networking & Access Control
# ------------------------------------------------------------------------------

variable "enable_private_endpoint" {
  description = "If true, disables the public Kubernetes API endpoint so the control plane is reachable only from private VPC networks. If false, external access is still restricted strictly to authorized_networks."
  type        = bool
  default     = false
}

variable "authorized_networks" {
  description = "List of CIDR blocks allowed to reach the Kubernetes API control plane (e.g., corporate VPN, CI/CD runners). Defaults to empty (deny all external IPs until explicitly authorized)."
  type = list(object({
    cidr_block   = string
    display_name = string
  }))
  default = []

  validation {
    condition     = alltrue([for n in var.authorized_networks : can(cidrnetmask(n.cidr_block))])
    error_message = "Every entry in authorized_networks must have a valid IPv4 CIDR block."
  }
}

variable "gcp_public_cidrs_access_enabled" {
  description = "Allow Google Cloud global public IP addresses to access the control plane endpoint."
  type        = bool
  default     = false
}

variable "default_max_pods_per_node" {
  description = "Default maximum number of pods per node. Defaults to 64 (allocating a /25 per node from the shared 'pods' secondary range instead of a /24, conserving pod IP space across clusters)."
  type        = number
  default     = 64

  validation {
    condition     = var.default_max_pods_per_node >= 8 && var.default_max_pods_per_node <= 110
    error_message = "default_max_pods_per_node must be between 8 and 110."
  }
}

variable "control_plane_webhook_ports" {
  description = "Optional extra TCP ports on worker nodes to allow from the GKE control plane for Kubernetes admission webhooks (e.g., [\"8443\", \"9443\", \"15017\"] for cert-manager, Gatekeeper, or Istio)."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for p in var.control_plane_webhook_ports : can(regex("^[0-9]{1,5}(-[0-9]{1,5})?$", p))])
    error_message = "Each entry in control_plane_webhook_ports must be a TCP port number or range (e.g., \"8443\" or \"8443-8445\")."
  }
}

# ------------------------------------------------------------------------------
# Security & Multi-Team Governance
# ------------------------------------------------------------------------------

variable "rbac_security_group" {
  description = "Optional Google Group email (must be named gke-security-groups@<your-domain>) to enable Google Groups for Kubernetes RBAC across product teams."
  type        = string
  default     = null

  validation {
    condition     = var.rbac_security_group == null || startswith(var.rbac_security_group, "gke-security-groups@")
    error_message = "rbac_security_group must start with \"gke-security-groups@\" as required by GKE."
  }
}

variable "database_encryption_kms_key" {
  description = "Optional Cloud KMS CryptoKey resource ID (projects/<project>/locations/<region>/keyRings/<ring>/cryptoKeys/<key>) for customer-managed application-layer encryption (CMEK) of Kubernetes Secrets in etcd."
  type        = string
  default     = null

  validation {
    condition = (
      var.database_encryption_kms_key == null ||
      can(regex("^projects/[^/]+/locations/[^/]+/keyRings/[^/]+/cryptoKeys/[^/]+$", var.database_encryption_kms_key))
    )
    error_message = "database_encryption_kms_key must be a full Cloud KMS CryptoKey ID (projects/<project>/locations/<location>/keyRings/<ring>/cryptoKeys/<key>)."
  }
}

variable "enable_binary_authorization" {
  description = "When true, enforces the project's Binary Authorization policy on container images deployed to this cluster."
  type        = bool
  default     = false
}

# ------------------------------------------------------------------------------
# Observability & Operations
# ------------------------------------------------------------------------------

variable "logging_components" {
  description = "GKE components that send logs to Cloud Logging."
  type        = list(string)
  default     = ["SYSTEM_COMPONENTS", "WORKLOADS"]
}

variable "monitoring_components" {
  description = "GKE components that send metrics to Cloud Monitoring."
  type        = list(string)
  default = [
    "SYSTEM_COMPONENTS",
    "APISERVER",
    "SCHEDULER",
    "CONTROLLER_MANAGER",
    "STORAGE",
    "POD",
    "DEPLOYMENT",
    "STATEFULSET",
    "DAEMONSET",
    "HPA",
  ]
}

variable "enable_managed_prometheus" {
  description = "Enable Google Cloud Managed Service for Prometheus so product teams can scrape Prometheus metrics without operating a Prometheus server."
  type        = bool
  default     = true
}

variable "notification_pubsub_topic" {
  description = "Optional Cloud Pub/Sub topic resource ID (projects/<project>/topics/<topic>) to receive GKE upgrade and security bulletin notifications."
  type        = string
  default     = null

  validation {
    condition = (
      var.notification_pubsub_topic == null ||
      can(regex("^projects/[^/]+/topics/[^/]+$", var.notification_pubsub_topic))
    )
    error_message = "notification_pubsub_topic must be a full Pub/Sub topic resource ID (projects/<project>/topics/<topic>)."
  }
}

variable "labels" {
  description = "Additional GCP resource labels to merge onto the cluster and its node pools."
  type        = map(string)
  default     = {}
}

# ------------------------------------------------------------------------------
# Node Pools
# ------------------------------------------------------------------------------

variable "node_pools" {
  description = "Map of managed node pools for this GKE Standard cluster. Defaults to a single resilient general-purpose pool spread across all zones in the region. Add or override pools for workload-specific machine types, taints, or Spot capacity."
  type = map(object({
    machine_type           = optional(string, "n2-standard-4")
    disk_size_gb           = optional(number, 100)
    disk_type              = optional(string, "pd-balanced")
    min_nodes_per_zone     = optional(number, 1)
    max_nodes_per_zone     = optional(number, 5)
    max_pods_per_node      = optional(number, null)
    spot                   = optional(bool, false)
    max_surge              = optional(number, 1)
    max_unavailable        = optional(number, 0)
    enable_gvnic           = optional(bool, true)
    enable_image_streaming = optional(bool, true)
    node_locations         = optional(list(string), [])
    node_labels            = optional(map(string), {})
    resource_labels        = optional(map(string), {})
    tags                   = optional(list(string), [])
    metadata               = optional(map(string), {})
    taints = optional(list(object({
      key    = string
      value  = string
      effect = string
    })), [])
  }))

  default = {
    general = {
      machine_type       = "n2-standard-4"
      disk_size_gb       = 100
      disk_type          = "pd-balanced"
      min_nodes_per_zone = 1
      max_nodes_per_zone = 5
      spot               = false
      max_surge          = 1
      max_unavailable    = 0
    }
  }

  validation {
    condition     = length(var.node_pools) > 0
    error_message = "At least one node pool must be configured in node_pools."
  }

  validation {
    condition = alltrue([
      for name, _ in var.node_pools :
      can(regex("^[a-z]([a-z0-9-]{0,11}[a-z0-9])?$", name))
    ])
    error_message = "Node pool keys must be 1-13 lowercase alphanumeric/hyphen characters (leaving room for GKE's unique name_prefix suffix during zero-downtime replacement)."
  }

  validation {
    condition = alltrue([
      for _, pool in var.node_pools :
      pool.min_nodes_per_zone >= 0 && pool.max_nodes_per_zone >= 1 && pool.max_nodes_per_zone >= pool.min_nodes_per_zone
    ])
    error_message = "Each node pool must have min_nodes_per_zone >= 0, max_nodes_per_zone >= 1, and max_nodes_per_zone >= min_nodes_per_zone."
  }

  validation {
    condition = alltrue([
      for _, pool in var.node_pools :
      pool.max_surge >= 0 && pool.max_unavailable >= 0 && (pool.max_surge + pool.max_unavailable) >= 1
    ])
    error_message = "Each node pool must have max_surge >= 0, max_unavailable >= 0, and max_surge + max_unavailable >= 1."
  }

  validation {
    condition = alltrue([
      for _, pool in var.node_pools :
      contains(["pd-balanced", "pd-ssd", "pd-standard", "hyperdisk-balanced"], pool.disk_type) && pool.disk_size_gb >= 30
    ])
    error_message = "Each node pool must use a supported disk_type (pd-balanced, pd-ssd, pd-standard, hyperdisk-balanced) and disk_size_gb >= 30."
  }

  validation {
    condition = alltrue(flatten([
      for _, pool in var.node_pools : [
        for t in pool.taints :
        contains(["NO_SCHEDULE", "PREFER_NO_SCHEDULE", "NO_EXECUTE"], t.effect)
      ]
    ]))
    error_message = "Taint effect must be one of NO_SCHEDULE, PREFER_NO_SCHEDULE, or NO_EXECUTE."
  }
}
