# ---------------------------------------------------------------------------
# What every cluster must state
# ---------------------------------------------------------------------------

variable "name" {
  description = "Cluster name. Unique per project and region, e.g. \"payments\" or \"shared-01\"."
  type        = string

  validation {
    condition     = can(regex("^[a-z]([-a-z0-9]{0,38}[a-z0-9])$", var.name))
    error_message = "name must be 2-40 characters, start with a lowercase letter, contain only lowercase letters, digits and hyphens, and not end with a hyphen."
  }
}

variable "environment" {
  description = "Environment the cluster belongs to. Selects the network team's VPC (apps-staging or apps-prod) and environment-specific defaults such as the release channel."
  type        = string

  validation {
    condition     = contains(["staging", "prod"], var.environment)
    error_message = "environment must be \"staging\" or \"prod\"."
  }
}

variable "region" {
  description = "US region for the cluster, e.g. \"us-central1\". The network team's subnet apps-<environment>-gke-<region> must already exist there."
  type        = string

  validation {
    condition     = can(regex("^us-(central|east|west|south)[0-9]+$", var.region))
    error_message = "region must be a US Google Cloud region such as us-central1, us-east1, us-east4 or us-west1 (a region, not a zone)."
  }
}

# ---------------------------------------------------------------------------
# What a cluster may tune
# ---------------------------------------------------------------------------

variable "project_id" {
  description = "Project that holds the environment's VPC; the cluster is created in the same project. Leave null to use the project configured in the environment (GOOGLE_PROJECT / GOOGLE_CLOUD_PROJECT)."
  type        = string
  default     = null
}

variable "zones" {
  description = "Zones (in var.region) that nodes run in. Leave null to let GKE spread nodes over its default zones for the region (normally three). If set, at least two zones are required so a zone outage does not take the workloads down."
  type        = list(string)
  default     = null

  validation {
    condition     = var.zones == null ? true : length(distinct(var.zones)) >= 2 && length(distinct(var.zones)) == length(var.zones)
    error_message = "zones must list at least two distinct zones, or be null."
  }
}

variable "node_pools" {
  description = <<-EOT
    Node pools, keyed by pool name. Node counts are PER ZONE: with the default
    three zones, min_nodes_per_zone = 1 means at least three nodes.

    Every pool gets, with no option to turn it off: the cluster's dedicated
    least-privilege node service account, Workload Identity (GKE metadata
    server), Shielded VM secure boot and integrity monitoring, Container-
    Optimized OS, auto-repair, auto-upgrade and zero-downtime surge upgrades.

    Changing machine_type, disk settings or spot recreates the node pool's
    nodes; add a new pool and drain the old one for a no-downtime change.
  EOT
  type = map(object({
    machine_type       = optional(string, "e2-standard-4")
    min_nodes_per_zone = optional(number, 1)
    max_nodes_per_zone = optional(number, 3)
    disk_size_gb       = optional(number, 100)
    disk_type          = optional(string, "pd-balanced")
    spot               = optional(bool, false)
    zones              = optional(list(string))
    labels             = optional(map(string), {})
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
    condition     = alltrue([for name, _ in var.node_pools : can(regex("^[a-z]([-a-z0-9]{0,38}[a-z0-9])?$", name))])
    error_message = "Node pool names must be 1-40 characters of lowercase letters, digits and hyphens, starting with a letter and not ending with a hyphen."
  }

  validation {
    condition = alltrue([
      for _, p in var.node_pools :
      p.min_nodes_per_zone >= 0 && p.max_nodes_per_zone >= 1 && p.min_nodes_per_zone <= p.max_nodes_per_zone
    ])
    error_message = "Each node pool needs 0 <= min_nodes_per_zone <= max_nodes_per_zone and max_nodes_per_zone >= 1."
  }

  validation {
    condition     = anytrue([for _, p in var.node_pools : !p.spot && p.min_nodes_per_zone >= 1 && length(p.taints) == 0])
    error_message = "At least one node pool must be on-demand (spot = false), untainted and have min_nodes_per_zone >= 1, so system workloads always have somewhere stable to run."
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
    condition     = alltrue([for _, p in var.node_pools : p.disk_size_gb >= 50])
    error_message = "disk_size_gb must be at least 50 so nodes have room for images and logs."
  }
}

variable "release_channel" {
  description = "GKE release channel that drives automatic control plane and node upgrades. Leave null for the module default: REGULAR in staging and STABLE in prod, so every version soaks in staging before it reaches production."
  type        = string
  default     = null

  validation {
    condition     = var.release_channel == null ? true : contains(["REGULAR", "STABLE"], var.release_channel)
    error_message = "release_channel must be \"REGULAR\", \"STABLE\" or null."
  }
}

variable "maintenance_window" {
  description = <<-EOT
    When GKE may run automatic upgrades and other disruptive maintenance.
    Times are UTC, HH:MM, and the window must not cross midnight UTC and must
    be at least four hours long. recurrence is an RFC 5545 RRULE. GKE requires
    at least 48 hours of window in any 32 days.

    The default (Tue-Thu 08:00-12:00 UTC) is the middle of the night across
    the US and never lands on a weekend or a Monday morning.
  EOT
  type = object({
    start_time_utc = optional(string, "08:00")
    end_time_utc   = optional(string, "12:00")
    recurrence     = optional(string, "FREQ=WEEKLY;BYDAY=TU,WE,TH")
  })
  default = {}

  validation {
    condition = (
      can(regex("^([01][0-9]|2[0-3]):[0-5][0-9]$", var.maintenance_window.start_time_utc)) &&
      can(regex("^([01][0-9]|2[0-3]):[0-5][0-9]$", var.maintenance_window.end_time_utc))
    )
    error_message = "maintenance_window start_time_utc and end_time_utc must be HH:MM (24h, UTC)."
  }

  validation {
    condition = try(
      (tonumber(substr(var.maintenance_window.end_time_utc, 0, 2)) * 60 + tonumber(substr(var.maintenance_window.end_time_utc, 3, 2))) -
      (tonumber(substr(var.maintenance_window.start_time_utc, 0, 2)) * 60 + tonumber(substr(var.maintenance_window.start_time_utc, 3, 2))) >= 240,
      false
    )
    error_message = "maintenance_window must end at least four hours after it starts, on the same UTC day."
  }
}

variable "master_authorized_networks" {
  description = <<-EOT
    Extra private CIDR ranges (inside the VPC or connected to it by VPN /
    Interconnect) allowed to reach the control plane's private IP endpoint.
    Usually empty: the control plane has no public IP endpoint, people and
    CI reach the cluster through the IAM-authenticated DNS endpoint, and the
    cluster's own nodes and pods are always allowed.
  EOT
  type = list(object({
    cidr_block   = string
    display_name = string
  }))
  default = []

  validation {
    condition     = alltrue([for n in var.master_authorized_networks : can(cidrhost(n.cidr_block, 0))])
    error_message = "Every master_authorized_networks cidr_block must be a valid CIDR range."
  }

  validation {
    condition     = alltrue([for n in var.master_authorized_networks : !contains(["0.0.0.0/0", "::/0"], n.cidr_block)])
    error_message = "master_authorized_networks must not contain 0.0.0.0/0."
  }
}

variable "rbac_security_group" {
  description = "Google Groups for RBAC: the Workspace group gke-security-groups@<your-domain> whose nested groups can be used as subjects in Kubernetes RoleBindings, so each product team is granted access to its namespaces by group instead of user by user. Null disables the feature."
  type        = string
  default     = null

  validation {
    condition     = var.rbac_security_group == null ? true : can(regex("^gke-security-groups@.+\\..+$", var.rbac_security_group))
    error_message = "rbac_security_group must be of the form gke-security-groups@<domain>; GKE requires that exact group name."
  }
}

variable "secrets_encryption_kms_key" {
  description = "Cloud KMS key (projects/<p>/locations/<region>/keyRings/<r>/cryptoKeys/<k>) used to encrypt Kubernetes Secrets in etcd. Leave null and the module creates and rotates a dedicated key for this cluster. If you bring your own key it must be in the cluster's region and you must grant the GKE service agent roles/cloudkms.cryptoKeyEncrypterDecrypter on it first."
  type        = string
  default     = null

  validation {
    condition     = var.secrets_encryption_kms_key == null ? true : can(regex("^projects/[^/]+/locations/[^/]+/keyRings/[^/]+/cryptoKeys/[^/]+$", var.secrets_encryption_kms_key))
    error_message = "secrets_encryption_kms_key must look like projects/<project>/locations/<location>/keyRings/<ring>/cryptoKeys/<key>."
  }
}

variable "deletion_protection" {
  description = "Refuse to destroy the cluster through OpenTofu. Keep true for anything teams depend on; to decommission a cluster, set false, apply, then destroy."
  type        = bool
  default     = true
}

variable "labels" {
  description = "Extra labels for the cluster and its nodes' cloud resources (for example cost-centre or owner). The module adds environment, cluster and managed-by itself."
  type        = map(string)
  default     = {}
}
