# ---------------------------------------------------------------------------
# Per-cluster inputs — what the platform team fills in for each new cluster.
# Everything else is owned by the module (see main.tf).
# ---------------------------------------------------------------------------

variable "name" {
  description = <<-EOT
    Cluster name. Also used to derive the node service account ID
    ("<name>-nodes"), so it is capped at 24 characters.
  EOT
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-z]([a-z0-9-]{0,22}[a-z0-9])?$", var.name))
    error_message = "name must be 1-24 characters: lowercase letters, digits and dashes; start with a letter and do not end with a dash."
  }
}

variable "region" {
  description = "Region for the cluster. The cluster is regional: control plane and nodes are spread across the zones of this region."
  type        = string
  nullable    = false
}

variable "network" {
  description = "Name of the environment VPC owned by the network team (e.g. \"apps-staging\" or \"apps-prod\"). The VPC lives in the same project as the cluster."
  type        = string
  nullable    = false
}

variable "master_ipv4_cidr_block" {
  description = <<-EOT
    RFC1918 /28 CIDR for the GKE control plane VPC peering. Must be unique per
    cluster and must not overlap with any range in the VPC or its peered
    networks. Ask the network team for an allocation.
  EOT
  type        = string
  nullable    = false

  validation {
    condition     = can(cidrhost(var.master_ipv4_cidr_block, 0)) && endswith(var.master_ipv4_cidr_block, "/28")
    error_message = "master_ipv4_cidr_block must be a valid /28 CIDR (e.g. \"172.16.0.0/28\") — GKE requires exactly a /28 for the control plane."
  }
}

# ---------------------------------------------------------------------------
# Placement / project
# ---------------------------------------------------------------------------

variable "project_id" {
  description = "Google Cloud project for the cluster (and the VPC). Defaults to the project configured on the google provider / in the environment credentials."
  type        = string
  default     = null
}

variable "subnetwork" {
  description = "Name of the GKE subnetwork inside var.network. Defaults to the network-team convention \"<network>-gke-<region>\". The subnetwork must already exist with secondary ranges named like var.pods_secondary_range_name / var.services_secondary_range_name."
  type        = string
  default     = null
}

# ---------------------------------------------------------------------------
# Release management
# ---------------------------------------------------------------------------

variable "release_channel" {
  description = "GKE release channel. REGULAR balances freshness and stability; use STABLE for the most conservative clusters."
  type        = string
  default     = "REGULAR"

  validation {
    condition     = contains(["RAPID", "REGULAR", "STABLE"], var.release_channel)
    error_message = "release_channel must be one of RAPID, REGULAR or STABLE."
  }
}

variable "kubernetes_version" {
  description = "Optional exact GKE version to pin (sets min_master_version). Leave null to follow the release channel's default version."
  type        = string
  default     = null
}

variable "maintenance_start_time" {
  description = "Start of the daily/weekly maintenance window (RFC3339, UTC)."
  type        = string
  default     = "2024-01-01T02:00:00Z"
}

variable "maintenance_end_time" {
  description = "End of the maintenance window (RFC3339, UTC). Must be at least 2 hours after the start."
  type        = string
  default     = "2024-01-01T06:00:00Z"
}

variable "maintenance_recurrence" {
  description = "RRULE for the maintenance window."
  type        = string
  default     = "FREQ=DAILY"
}

# ---------------------------------------------------------------------------
# Network conventions (defaults match the network team's standard)
# ---------------------------------------------------------------------------

variable "pods_secondary_range_name" {
  description = "Name of the subnetwork secondary range used for pod IPs."
  type        = string
  default     = "pods"
}

variable "services_secondary_range_name" {
  description = "Name of the subnetwork secondary range used for service (ClusterIP) IPs."
  type        = string
  default     = "services"
}

variable "enable_private_nodes" {
  description = "Give nodes only internal IPs. Requires outbound access to Google APIs (Private Google Access) and to the internet (e.g. Cloud NAT) for public image pulls — the network team's subnets normally provide this."
  type        = bool
  default     = true
  nullable    = false
}

variable "enable_private_endpoint" {
  description = "Disable the control plane's public endpoint. If true, the API server is only reachable from inside the VPC (or peered networks); make sure the apply/kubectl path runs from inside the VPC."
  type        = bool
  default     = false
  nullable    = false
}

variable "master_authorized_networks" {
  description = "CIDR blocks allowed to reach the control plane endpoint (TLS + IAM still required). Empty means reachable from any source IP — set this to lock the endpoint down to e.g. office/VPN ranges."
  type = list(object({
    cidr_block   = string
    display_name = optional(string, "")
  }))
  default  = []
  nullable = false
}

# ---------------------------------------------------------------------------
# Node pools
# ---------------------------------------------------------------------------

variable "node_pools" {
  description = <<-EOT
    Node pools to create, keyed by pool name. Every attribute is optional; the
    defaults describe a general-purpose pool suitable for production.

    autoscaling (default true) uses min_count/max_count *per zone* — a regional
    cluster usually spans 3 zones, so min_count = 1 keeps ~3 nodes running.
    Set autoscaling = false and node_count (also per zone) for a fixed size.

    Example:
      node_pools = {
        default = { machine_type = "n2-standard-8", max_count = 10 }
        batch   = {
          spot         = true
          machine_type = "e2-standard-4"
          taints       = [{ key = "spot", value = "true", effect = "NO_SCHEDULE" }]
        }
      }
  EOT
  type = map(object({
    machine_type    = optional(string, "e2-standard-4")
    image_type      = optional(string, "COS_CONTAINERD")
    disk_type       = optional(string, "pd-balanced")
    disk_size_gb    = optional(number, 100)
    spot            = optional(bool, false)
    autoscaling     = optional(bool, true)
    min_count       = optional(number, 1)
    max_count       = optional(number, 6)
    node_count      = optional(number, 1) # only used when autoscaling = false
    node_locations  = optional(list(string))
    labels          = optional(map(string), {})
    tags            = optional(list(string), [])
    taints          = optional(list(object({ key = string, value = string, effect = string })), [])
    auto_repair     = optional(bool, true)
    auto_upgrade    = optional(bool, true)
    max_surge       = optional(number, 1)
    max_unavailable = optional(number, 0)
  }))
  default = {
    default = {}
  }
  nullable = false

  validation {
    condition     = length(var.node_pools) > 0
    error_message = "At least one node pool is required."
  }

  validation {
    condition     = alltrue([for name in keys(var.node_pools) : can(regex("^[a-z][a-z0-9-]{0,39}$", name))])
    error_message = "Node pool names must start with a lowercase letter, contain only lowercase letters, digits and dashes, and be at most 40 characters."
  }

  validation {
    condition     = alltrue([for pool in values(var.node_pools) : !pool.autoscaling || pool.min_count <= pool.max_count])
    error_message = "For every autoscaling node pool, min_count must be <= max_count."
  }
}

variable "node_service_account_extra_roles" {
  description = "Extra project-level IAM roles to grant the nodes' service account, on top of the module's minimal set (logging, monitoring, metadata, Artifact Registry reader)."
  type        = list(string)
  default     = []
  nullable    = false
}

# ---------------------------------------------------------------------------
# Governance / integrations
# ---------------------------------------------------------------------------

variable "labels" {
  description = "GCP resource labels applied to the cluster (useful for cost allocation per cluster/team)."
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "authenticator_security_group" {
  description = "Optional Google Workspace security group (e.g. \"gke-security-groups@example.com\") to enable Google Groups-based RBAC."
  type        = string
  default     = null
}

variable "upgrade_notification_topic" {
  description = "Optional Pub/Sub topic (\"projects/<p>/topics/<t>\") receiving GKE upgrade notifications. Strongly recommended so the platform team is warned about upcoming upgrades."
  type        = string
  default     = null
}

variable "enable_managed_prometheus" {
  description = "Enable Google Cloud Managed Service for Prometheus collection for the cluster."
  type        = bool
  default     = true
  nullable    = false
}

variable "enable_binary_authorization" {
  description = "Enforce the project's Binary Authorization policy on deployed images. The default project policy allows all images; enable only once a policy is in place."
  type        = bool
  default     = false
  nullable    = false
}

variable "deletion_protection" {
  description = "Prevent accidental cluster deletion. Flip to true for clusters carrying production traffic; destroying then requires setting it to false first."
  type        = bool
  default     = false
  nullable    = false
}
