###############################################################################
# What every cluster must state
###############################################################################

variable "name" {
  description = "Cluster name. Must be unique per project and region, e.g. \"prod-usc1\"."
  type        = string

  validation {
    condition     = can(regex("^[a-z]([-a-z0-9]{0,38}[a-z0-9])?$", var.name))
    error_message = "name must be 1-40 characters of lowercase letters, digits and hyphens, start with a letter and not end with a hyphen."
  }
}

variable "environment" {
  description = "Environment the cluster belongs to. Selects the network team's VPC (apps-<environment>) and the default release channel."
  type        = string

  validation {
    condition     = contains(["staging", "prod"], var.environment)
    error_message = "environment must be \"staging\" or \"prod\" (the VPCs that exist are apps-staging and apps-prod)."
  }
}

variable "region" {
  description = "US region for the cluster, e.g. \"us-central1\". The cluster is regional and uses the subnet apps-<environment>-gke-<region>."
  type        = string

  validation {
    condition     = can(regex("^us-[a-z]+[0-9]+$", var.region))
    error_message = "region must be a US region such as us-central1 or us-east4 (a region, not a zone). GKE subnets only exist in US regions."
  }
}

###############################################################################
# Optional, with production-safe defaults
###############################################################################

variable "project_id" {
  description = "Project that holds the apps-<environment> VPC and will hold the cluster. Defaults to the project configured in the environment (e.g. GOOGLE_PROJECT)."
  type        = string
  default     = null

  validation {
    condition     = var.project_id == null || can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", coalesce(var.project_id, "unset")))
    error_message = "project_id must be a project ID (6-30 lowercase letters, digits and hyphens), not a project name or number."
  }
}

variable "node_pools" {
  description = <<-EOT
    Node pools, keyed by pool name. Every pool spans all zones of the region,
    autoscales between min_nodes_per_zone and max_nodes_per_zone in each zone,
    and is auto-repaired and auto-upgraded with surge upgrades.

    At least one pool must be on-demand (spot = false), untainted and have
    min_nodes_per_zone >= 1, so system workloads always have a place in every zone.

    Changing machine_type, disk settings, spot or taints replaces the pool's
    nodes; to do that without disruption add a new pool, move workloads, then
    remove the old one.
  EOT
  type = map(object({
    machine_type       = optional(string, "e2-standard-4")
    min_nodes_per_zone = optional(number, 1)
    max_nodes_per_zone = optional(number, 5)
    disk_size_gb       = optional(number, 100)
    disk_type          = optional(string, "pd-balanced")
    spot               = optional(bool, false)
    labels             = optional(map(string), {})
    taints = optional(list(object({
      key    = string
      value  = string
      effect = string
    })), [])
  }))
  default = {
    default = {}
  }

  validation {
    condition     = alltrue([for name, _ in var.node_pools : can(regex("^[a-z]([-a-z0-9]{0,38}[a-z0-9])?$", name))])
    error_message = "Node pool names must be 1-40 characters of lowercase letters, digits and hyphens, start with a letter and not end with a hyphen."
  }

  validation {
    condition = alltrue([
      for _, p in var.node_pools :
      p.min_nodes_per_zone >= 0 && p.max_nodes_per_zone >= 1 && p.min_nodes_per_zone <= p.max_nodes_per_zone
    ])
    error_message = "Each node pool needs 0 <= min_nodes_per_zone <= max_nodes_per_zone and max_nodes_per_zone >= 1."
  }

  validation {
    condition = alltrue(flatten([
      for _, p in var.node_pools : [
        for t in p.taints : contains(["NO_SCHEDULE", "PREFER_NO_SCHEDULE", "NO_EXECUTE"], t.effect)
      ]
    ]))
    error_message = "Taint effect must be NO_SCHEDULE, PREFER_NO_SCHEDULE or NO_EXECUTE."
  }

  validation {
    condition = anytrue([
      for _, p in var.node_pools :
      !p.spot && length(p.taints) == 0 && p.min_nodes_per_zone >= 1
    ])
    error_message = "At least one node pool must be on-demand (spot = false), have no taints and have min_nodes_per_zone >= 1, so system workloads can always run in every zone."
  }
}

variable "release_channel" {
  description = "GKE release channel. Leave null for the standard rollout order: staging on REGULAR, prod on STABLE, so every version runs in staging before it reaches prod."
  type        = string
  default     = null

  validation {
    condition     = var.release_channel == null || contains(["REGULAR", "STABLE"], coalesce(var.release_channel, "unset"))
    error_message = "release_channel must be REGULAR or STABLE (or null for the environment default)."
  }
}

variable "maintenance_window" {
  description = <<-EOT
    Recurring window in which GKE may run automatic upgrades and maintenance.
    Default: Tuesday-Thursday 07:00-12:00 UTC (night / early morning across US time zones,
    never next to a weekend). GKE requires at least 48 hours of window in any 32 days,
    in stretches of 4 hours or more.
  EOT
  type = object({
    start_time = string
    end_time   = string
    recurrence = string
  })
  default = {
    start_time = "2025-01-07T07:00:00Z"
    end_time   = "2025-01-07T12:00:00Z"
    recurrence = "FREQ=WEEKLY;BYDAY=TU,WE,TH"
  }

  validation {
    condition = (
      can(regex("^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}Z$", var.maintenance_window.start_time)) &&
      can(regex("^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}Z$", var.maintenance_window.end_time)) &&
      can(regex("^FREQ=(DAILY|WEEKLY)", var.maintenance_window.recurrence))
    )
    error_message = "maintenance_window times must be RFC 3339 UTC timestamps (e.g. 2025-01-07T07:00:00Z) and recurrence an RRULE starting with FREQ=DAILY or FREQ=WEEKLY."
  }
}

variable "maintenance_exclusions" {
  description = "Periods in which automatic upgrades are blocked, e.g. a change freeze. Times are RFC 3339 UTC. scope is NO_UPGRADES (max 30 days), NO_MINOR_UPGRADES or NO_MINOR_OR_NODE_UPGRADES."
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
    error_message = "maintenance_exclusions scope must be NO_UPGRADES, NO_MINOR_UPGRADES or NO_MINOR_OR_NODE_UPGRADES."
  }
}

variable "control_plane_dns_endpoint_external_access" {
  description = <<-EOT
    Whether the control plane's DNS-based endpoint accepts connections from outside the VPC.
    Every request through it must carry Google credentials with IAM permission on the cluster;
    Kubernetes tokens and client certificates are not accepted there. This is how engineers and CI
    reach the cluster (gcloud container clusters get-credentials --dns-endpoint).
    Set to false only if all access comes from inside the VPC.
  EOT
  type        = bool
  default     = true
}

variable "control_plane_authorized_networks" {
  description = <<-EOT
    Internal CIDR ranges (VPN, bastion, CI runners in the VPC or connected networks) that may reach
    the control plane's private IP endpoint, in addition to the cluster's own subnet.
    The control plane has no public IP endpoint, so public ranges have no effect here.
  EOT
  type = list(object({
    name       = string
    cidr_block = string
  }))
  default = []

  validation {
    condition     = alltrue([for n in var.control_plane_authorized_networks : can(cidrhost(n.cidr_block, 0))])
    error_message = "Each control_plane_authorized_networks cidr_block must be a valid CIDR range, e.g. 10.20.0.0/24."
  }

  validation {
    condition     = alltrue([for n in var.control_plane_authorized_networks : !endswith(n.cidr_block, "/0")])
    error_message = "control_plane_authorized_networks must not contain a /0 range."
  }
}

variable "rbac_security_group" {
  description = "Google Group that enables Google Groups in Kubernetes RBAC, so teams can be granted namespace access by group. Must be named gke-security-groups@<your-domain> and contain the team groups as members."
  type        = string
  default     = null

  validation {
    condition     = var.rbac_security_group == null || can(regex("^gke-security-groups@.+\\..+$", coalesce(var.rbac_security_group, "unset")))
    error_message = "rbac_security_group must be of the form gke-security-groups@<your-domain>."
  }
}

variable "secrets_encryption_kms_key" {
  description = "Cloud KMS key (projects/<p>/locations/<l>/keyRings/<r>/cryptoKeys/<k>) used to encrypt Kubernetes Secrets at the application layer. The key must be in the cluster's region and the GKE service agent needs roles/cloudkms.cryptoKeyEncrypterDecrypter on it. Null keeps Google-managed encryption at rest."
  type        = string
  default     = null

  validation {
    condition     = var.secrets_encryption_kms_key == null || can(regex("^projects/[^/]+/locations/[^/]+/keyRings/[^/]+/cryptoKeys/[^/]+$", coalesce(var.secrets_encryption_kms_key, "unset")))
    error_message = "secrets_encryption_kms_key must look like projects/<project>/locations/<location>/keyRings/<ring>/cryptoKeys/<key>."
  }
}

variable "enable_binary_authorization" {
  description = "Enforce the project's Binary Authorization policy on the cluster. Requires the Binary Authorization API and a reviewed project policy, so it is opt-in."
  type        = bool
  default     = false
}

variable "labels" {
  description = "Extra labels for the cluster and its nodes (e.g. cost-center). The module always sets environment, cluster and managed-by."
  type        = map(string)
  default     = {}

  validation {
    condition = alltrue([
      for k, v in var.labels :
      can(regex("^[a-z][a-z0-9_-]{0,62}$", k)) && can(regex("^[a-z0-9_-]{0,63}$", v))
    ])
    error_message = "Label keys must start with a lowercase letter; keys and values may contain only lowercase letters, digits, underscores and hyphens (max 63 characters)."
  }
}

variable "deletion_protection" {
  description = "Block deletion of the cluster through OpenTofu. To retire a cluster, set this to false, apply, then destroy."
  type        = bool
  default     = true
}
