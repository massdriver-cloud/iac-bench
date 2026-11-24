# ---------------------------------------------------------------------------
# What is specific to each cluster (no defaults - you must fill these in)
# ---------------------------------------------------------------------------

variable "name" {
  description = "Cluster name. Must be unique within the project (it also names the cluster's node service account). Lowercase letters, digits and hyphens, 3-24 characters, starting with a letter."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,22}[a-z0-9]$", var.name))
    error_message = "name must be 3-24 characters of lowercase letters, digits and hyphens, start with a letter and not end with a hyphen."
  }
}

variable "environment" {
  description = "Environment the cluster belongs to. Selects the VPC the network team owns: \"staging\" -> apps-staging, \"prod\" -> apps-prod."
  type        = string

  validation {
    condition     = contains(["staging", "prod"], var.environment)
    error_message = "environment must be \"staging\" or \"prod\"."
  }
}

variable "region" {
  description = "US region for the cluster, e.g. \"us-central1\". The cluster is regional (control plane and nodes spread over the region's zones) and attaches to the subnet apps-<environment>-gke-<region>."
  type        = string

  validation {
    condition     = can(regex("^us-[a-z]+[0-9]+$", var.region))
    error_message = "region must be a US region such as us-central1, us-east1, us-east4 or us-west1 - the network team only provides GKE subnets in US regions."
  }
}

# ---------------------------------------------------------------------------
# Optional - the defaults are the platform standard
# ---------------------------------------------------------------------------

variable "project_id" {
  description = "Project that holds the apps-staging / apps-prod VPCs; the cluster is created in it. Leave null to use the project your credentials/environment are configured for (e.g. GOOGLE_PROJECT)."
  type        = string
  default     = null

  validation {
    condition     = var.project_id == null || can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "project_id must be a project ID (not a project number or display name)."
  }
}

variable "node_pools" {
  description = <<-EOT
    Node pools, keyed by pool name. Node counts are PER ZONE: the cluster spans
    the region's zones (normally three), so min_nodes_per_zone = 1 means three
    nodes. Every pool autoscales between min and max, auto-repairs, auto-upgrades
    and is upgraded by surge (no capacity loss during upgrades).

    - machine_type        Compute Engine machine type.
    - min_nodes_per_zone  Autoscaling floor per zone.
    - max_nodes_per_zone  Autoscaling ceiling per zone.
    - disk_size_gb        Boot disk size.
    - disk_type           pd-balanced, pd-ssd or pd-standard.
    - spot                Use Spot VMs (cheaper, can be reclaimed at any time). Never the only pool.
    - zones               Restrict the pool to these zones; null = all the cluster's zones.
    - labels              Kubernetes node labels (for nodeSelector / affinity).
    - taints              Kubernetes taints, to dedicate a pool to workloads that tolerate them.

    At least one pool must be untainted, non-spot and have min_nodes_per_zone >= 1
    so that system workloads always have somewhere stable to run.
  EOT
  type = map(object({
    machine_type       = optional(string, "e2-standard-4")
    min_nodes_per_zone = optional(number, 1)
    max_nodes_per_zone = optional(number, 5)
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
    default = {}
  }

  validation {
    condition     = alltrue([for name, _ in var.node_pools : can(regex("^[a-z][a-z0-9-]{0,38}[a-z0-9]$", name))])
    error_message = "Node pool names must be 2-40 characters of lowercase letters, digits and hyphens, start with a letter and not end with a hyphen."
  }

  validation {
    condition = alltrue([
      for _, p in var.node_pools :
      p.min_nodes_per_zone >= 0 && p.max_nodes_per_zone >= 1 && p.min_nodes_per_zone <= p.max_nodes_per_zone
      && floor(p.min_nodes_per_zone) == p.min_nodes_per_zone && floor(p.max_nodes_per_zone) == p.max_nodes_per_zone
    ])
    error_message = "For every node pool: 0 <= min_nodes_per_zone <= max_nodes_per_zone, max_nodes_per_zone >= 1, both whole numbers."
  }

  validation {
    condition     = alltrue([for _, p in var.node_pools : contains(["pd-balanced", "pd-ssd", "pd-standard"], p.disk_type) && p.disk_size_gb >= 30])
    error_message = "For every node pool: disk_type must be pd-balanced, pd-ssd or pd-standard, and disk_size_gb at least 30."
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
    condition     = alltrue([for _, p in var.node_pools : p.zones == null ? true : length(p.zones) >= 1])
    error_message = "A node pool's zones must be null (all cluster zones) or a non-empty list."
  }

  validation {
    condition = length([
      for _, p in var.node_pools : true
      if !p.spot && length(p.taints) == 0 && p.min_nodes_per_zone >= 1
    ]) >= 1
    error_message = "At least one node pool must be non-spot, untainted and have min_nodes_per_zone >= 1, so system workloads always have stable capacity in every zone."
  }
}

variable "release_channel" {
  description = "GKE release channel that drives automatic upgrades: \"REGULAR\" or \"STABLE\". Null (default) picks REGULAR for staging and STABLE for prod, so every version runs in staging before it reaches prod."
  type        = string
  default     = null

  validation {
    condition     = var.release_channel == null || contains(["REGULAR", "STABLE"], coalesce(var.release_channel, "REGULAR"))
    error_message = "release_channel must be \"REGULAR\", \"STABLE\" or null."
  }
}

variable "maintenance_window" {
  description = <<-EOT
    When GKE may run automatic upgrades and maintenance. Times are UTC.
    Default: Tuesday-Thursday 06:00-12:00 UTC (overnight across US time zones,
    never on a weekend or a Monday/Friday).

    - start_time      "HH:MM" in UTC.
    - duration_hours  Window length, 4-24.
    - days            Any of MO, TU, WE, TH, FR, SA, SU.

    GKE requires at least 48 hours of window per 32 days, so
    duration_hours x number of days must be at least 12.
  EOT
  type = object({
    start_time     = optional(string, "06:00")
    duration_hours = optional(number, 6)
    days           = optional(list(string), ["TU", "WE", "TH"])
  })
  default = {}

  validation {
    condition     = can(regex("^([01][0-9]|2[0-3]):[0-5][0-9]$", var.maintenance_window.start_time))
    error_message = "maintenance_window.start_time must be HH:MM (24h, UTC)."
  }

  validation {
    condition = (
      var.maintenance_window.duration_hours >= 4 &&
      var.maintenance_window.duration_hours <= 24 &&
      floor(var.maintenance_window.duration_hours) == var.maintenance_window.duration_hours
    )
    error_message = "maintenance_window.duration_hours must be a whole number between 4 and 24."
  }

  validation {
    condition = (
      length(var.maintenance_window.days) >= 1 &&
      length(distinct(var.maintenance_window.days)) == length(var.maintenance_window.days) &&
      alltrue([for d in var.maintenance_window.days : contains(["MO", "TU", "WE", "TH", "FR", "SA", "SU"], d)])
    )
    error_message = "maintenance_window.days must be a non-empty list of distinct values from MO, TU, WE, TH, FR, SA, SU."
  }

  validation {
    condition     = var.maintenance_window.duration_hours * length(var.maintenance_window.days) >= 12
    error_message = "The maintenance window is too small: duration_hours x number of days must be at least 12 (GKE needs 48 hours of window per 32 days)."
  }
}

variable "control_plane_authorized_networks" {
  description = "Internal CIDR ranges (in the VPC or connected to it, e.g. a bastion or CI runner subnet) allowed to reach the control plane's private IP endpoint. Usually not needed: engineers and CI reach the cluster through its IAM-authenticated DNS endpoint. The control plane never has a public IP endpoint."
  type = list(object({
    name = string
    cidr = string
  }))
  default = []

  validation {
    condition     = alltrue([for n in var.control_plane_authorized_networks : can(cidrhost(n.cidr, 0))])
    error_message = "Every control_plane_authorized_networks entry needs a valid IPv4 CIDR, e.g. 10.20.0.0/24."
  }
}

variable "rbac_security_group" {
  description = "Enables Google Groups for RBAC so product teams can be bound to Kubernetes roles by group. Must be the group named gke-security-groups@<your-domain>, which contains the teams' groups. Null disables the feature."
  type        = string
  default     = null

  validation {
    condition     = var.rbac_security_group == null || can(regex("^gke-security-groups@.+\\..+$", var.rbac_security_group))
    error_message = "rbac_security_group must be of the form gke-security-groups@<your-domain>."
  }
}

variable "secrets_encryption_kms_key" {
  description = "Cloud KMS key (projects/<p>/locations/<l>/keyRings/<r>/cryptoKeys/<k>) used to encrypt Kubernetes Secrets at the application layer, on top of Google's default at-rest encryption. The GKE service agent must already hold roles/cloudkms.cryptoKeyEncrypterDecrypter on the key. Null keeps Google-managed encryption only."
  type        = string
  default     = null

  validation {
    condition     = var.secrets_encryption_kms_key == null || can(regex("^projects/[^/]+/locations/[^/]+/keyRings/[^/]+/cryptoKeys/[^/]+$", var.secrets_encryption_kms_key))
    error_message = "secrets_encryption_kms_key must look like projects/<project>/locations/<location>/keyRings/<ring>/cryptoKeys/<key>."
  }
}

variable "enable_binary_authorization" {
  description = "Enforce the project's Binary Authorization policy on every image deployed to the cluster. Requires the Binary Authorization API and a policy the product teams' images satisfy, so it is opt-in."
  type        = bool
  default     = false
}

variable "labels" {
  description = "Extra labels for the cluster and its nodes (e.g. cost centre). The module always adds environment, cluster and managed-by."
  type        = map(string)
  default     = {}

  validation {
    condition = alltrue([
      for k, v in var.labels : can(regex("^[a-z][a-z0-9_-]{0,62}$", k)) && can(regex("^[a-z0-9_-]{0,63}$", v))
    ])
    error_message = "Label keys and values may only contain lowercase letters, digits, underscores and hyphens (max 63 characters); keys must start with a letter."
  }
}

variable "deletion_protection" {
  description = "Blocks `tofu destroy` (and any change that would replace the cluster). To retire a cluster, first apply with this set to false, then destroy."
  type        = bool
  default     = true
}
