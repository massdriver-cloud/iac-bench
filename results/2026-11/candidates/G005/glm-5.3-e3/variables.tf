# ---------------------------------------------------------------------------
# Required inputs. These are the only things that genuinely differ between
# clusters; everything else has a production-ready default.
# ---------------------------------------------------------------------------

variable "project_id" {
  description = "Project that hosts the environment VPC. By design, the cluster is always created in the same project as its VPC."
  type        = string
}

variable "region" {
  description = "US region for the cluster, for example us-central1. The network team's subnet '<vpc_name>-gke-<region>' must already exist there. Clusters are created regional, so the control plane and nodes are replicated across the region's zones."
  type        = string

  validation {
    condition     = can(regex("^us-[a-z]+[0-9]+$", var.region))
    error_message = "The region must be a US region such as us-central1 or us-west2 (the network team's GKE subnets exist only in US regions), and it must be a region, not a zone."
  }
}

variable "vpc_name" {
  description = "Name of the network team's environment VPC (apps-staging or apps-prod). The cluster attaches to the subnet '<vpc_name>-gke-<region>' and its 'pods' and 'services' secondary ranges."
  type        = string

  validation {
    condition     = can(regex("^[a-z]([a-z0-9-]*[a-z0-9])?$", var.vpc_name))
    error_message = "The VPC name must start with a lowercase letter and contain only lowercase letters, digits and hyphens, for example apps-prod."
  }
}

variable "cluster_name" {
  description = "Name of the cluster. Leave unset to use the standard '<vpc_name>-<region>', for example apps-prod-us-central1."
  type        = string
  default     = null

  validation {
    condition     = var.cluster_name == null || (can(regex("^[a-z]([a-z0-9-]*[a-z0-9])?$", var.cluster_name)) && length(var.cluster_name) <= 40)
    error_message = "Cluster names must start with a lowercase letter, contain only lowercase letters, digits and hyphens, end with a letter or digit, and be at most 40 characters long."
  }
}

variable "control_plane_ipv4_cidr" {
  description = "RFC 1918 /28 CIDR block for the cluster's private control plane. Must be unique per cluster in the VPC: ask the network team for a fresh allocation for each new cluster. Example: 172.16.8.0/28."
  type        = string

  validation {
    condition     = try(parseint(split("/", var.control_plane_ipv4_cidr)[1], 10) == 28 && can(cidrhost(var.control_plane_ipv4_cidr, 0)), false)
    error_message = "control_plane_ipv4_cidr must be a /28 CIDR block, for example 172.16.8.0/28, and must not be in use by another cluster or range in the VPC."
  }
}

# ---------------------------------------------------------------------------
# Networking. Defaults follow the network team's conventions.
# ---------------------------------------------------------------------------

variable "subnet_name" {
  description = "GKE subnet name. Defaults to the network team's standard '<vpc_name>-gke-<region>'."
  type        = string
  default     = null
}

variable "pods_secondary_range_name" {
  description = "Secondary range on the GKE subnet that holds pod IPs. The network team's standard name is 'pods'."
  type        = string
  default     = "pods"

  validation {
    condition     = var.pods_secondary_range_name != ""
    error_message = "pods_secondary_range_name must not be empty."
  }
}

variable "services_secondary_range_name" {
  description = "Secondary range on the GKE subnet that holds Service ClusterIPs. The network team's standard name is 'services'."
  type        = string
  default     = "services"

  validation {
    condition     = var.services_secondary_range_name != ""
    error_message = "services_secondary_range_name must not be empty."
  }
}

# ---------------------------------------------------------------------------
# Control plane exposure.
# ---------------------------------------------------------------------------

variable "enable_private_endpoint" {
  description = "Whether the control plane endpoint is reachable only from the VPC and the ranges in master_authorized_networks. true is the secure default: reach the cluster from a jump host, VPN or Interconnect inside the VPC. When false the endpoint is public, and master_authorized_networks must list the CIDRs allowed to reach it."
  type        = bool
  default     = true
}

variable "master_authorized_networks" {
  description = "CIDR blocks allowed to reach the control plane endpoint, for example ['203.0.113.0/24'] for office or VPN ranges. Required whenever enable_private_endpoint is false; with a private endpoint these are non-VPC ranges (on-prem via Interconnect/VPN) that should also be allowed."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for cidr in var.master_authorized_networks : can(cidrhost(cidr, 0))])
    error_message = "Every entry in master_authorized_networks must be a valid CIDR block, for example 203.0.113.0/24."
  }
}

# ---------------------------------------------------------------------------
# Upgrades, maintenance and lifecycle.
# ---------------------------------------------------------------------------

variable "release_channel" {
  description = "GKE release channel that drives the cluster's upgrade cadence. REGULAR is recommended for production: Kubernetes versions that have passed GKE's testing, on a predictable schedule."
  type        = string
  default     = "REGULAR"

  validation {
    condition     = contains(["RAPID", "REGULAR", "STABLE"], var.release_channel)
    error_message = "release_channel must be one of RAPID, REGULAR or STABLE."
  }
}

variable "maintenance_start_time" {
  description = "UTC time (HH:MM) when the daily maintenance window, in which GKE may upgrade the control plane, starts."
  type        = string
  default     = "04:00"

  validation {
    condition     = can(regex("^([01][0-9]|2[0-3]):[0-5][0-9]$", var.maintenance_start_time))
    error_message = "maintenance_start_time must be a UTC time in HH:MM format, for example 04:00."
  }
}

variable "deletion_protection" {
  description = "Protects the cluster against accidental destruction. Set to false (and re-apply) only when a cluster is being retired."
  type        = bool
  default     = true
}

# ---------------------------------------------------------------------------
# Node pools.
# ---------------------------------------------------------------------------

variable "node_pools" {
  description = <<-EOT
    Workload node pools, in addition to the module-managed 'system' pool.
    Node counts are per zone: regional clusters replicate every pool across
    the region's zones, so min_size 1 means at least 3 nodes in total.

    name         (required) Pool name; lowercase letters, digits, hyphens.
    machine_type (required) For example e2-standard-4 or c3-standard-8.
    min_size     (optional) Minimum nodes per zone. Default 1.
    max_size     (optional) Maximum nodes per zone. Default 3.
    disk_size_gb (optional) Boot disk size in GB. Default 100.
    disk_type    (optional) pd-balanced (default), pd-ssd or hyperdisk-balanced.
    spot         (optional) Run the pool on Spot VMs. Default false.
    labels       (optional) Labels applied to the pool's nodes.
    tags         (optional) Network tags applied to the pool's nodes.
    taints       (optional) Taints that dedicate the pool to workloads
                 tolerating them; effect is NO_SCHEDULE, PREFER_NO_SCHEDULE
                 or NO_EXECUTE.
  EOT
  type = list(object({
    name         = string
    machine_type = string
    min_size     = optional(number)
    max_size     = optional(number)
    disk_size_gb = optional(number)
    disk_type    = optional(string)
    spot         = optional(bool)
    labels       = optional(map(string))
    tags         = optional(list(string))
    taints = optional(list(object({
      key    = string
      value  = string
      effect = string
    })))
  }))
  default = []

  validation {
    condition     = alltrue([for pool in var.node_pools : can(regex("^[a-z]([a-z0-9-]*[a-z0-9])?$", pool.name)) && length(pool.name) <= 40])
    error_message = "Node pool names must start with a lowercase letter, contain only lowercase letters, digits and hyphens, end with a letter or digit, and be at most 40 characters long."
  }

  validation {
    condition     = alltrue([for pool in var.node_pools : coalesce(pool.min_size, 1) <= coalesce(pool.max_size, 3)])
    error_message = "Every node pool needs min_size (default 1) less than or equal to max_size (default 3)."
  }

  validation {
    condition     = alltrue([for pool in var.node_pools : pool.name != "system"])
    error_message = "The name 'system' is reserved for the module-managed system node pool."
  }

  validation {
    condition = alltrue([
      for pool in var.node_pools : alltrue([
        for taint in(pool.taints == null ? [] : pool.taints) : contains(["NO_SCHEDULE", "PREFER_NO_SCHEDULE", "NO_EXECUTE"], taint.effect)
      ])
    ])
    error_message = "Taint effects must be one of NO_SCHEDULE, PREFER_NO_SCHEDULE or NO_EXECUTE."
  }
}

variable "create_system_node_pool" {
  description = "Create the 'system' node pool: smaller machines reserved for GKE system components and observability agents, so shared add-ons never compete with product workloads for capacity."
  type        = bool
  default     = true
}

variable "system_node_pool_machine_type" {
  description = "Machine type of the 'system' node pool."
  type        = string
  default     = "e2-standard-2"
}

variable "system_node_pool_min_size" {
  description = "Minimum number of 'system' nodes per zone."
  type        = number
  default     = 1
}

variable "system_node_pool_max_size" {
  description = "Maximum number of 'system' nodes per zone."
  type        = number
  default     = 2
}

# ---------------------------------------------------------------------------
# Node identity.
# ---------------------------------------------------------------------------

variable "create_node_service_account" {
  description = "Create a dedicated, least-privilege service account for this cluster's nodes, instead of running nodes on the Compute Engine default service account. Strongly recommended for production."
  type        = bool
  default     = true
}

variable "node_service_account_email" {
  description = "Email of an existing service account to run the nodes on. Only used when create_node_service_account is false. Leaving it null makes the module refuse to plan rather than fall back to the Compute Engine default service account."
  type        = string
  default     = null
}

variable "node_service_account_roles" {
  description = "IAM roles granted to the module-created node service account: the minimum GKE system agents need to ship logs and metrics. Add 'roles/artifactregistry.reader' if the cluster pulls images from private Artifact Registry repositories."
  type        = list(string)
  default = [
    "roles/monitoring.metricWriter",
    "roles/logging.logWriter",
  ]
}

variable "node_oauth_scopes" {
  description = "OAuth scopes granted to the nodes' service account credentials. The default set is GKE's least-privilege set (notably no cloud-platform scope); workloads that need Google Cloud APIs must use Workload Identity instead of wider scopes."
  type        = list(string)
  default = [
    "https://www.googleapis.com/auth/devstorage.read_only",
    "https://www.googleapis.com/auth/logging.write",
    "https://www.googleapis.com/auth/monitoring",
    "https://www.googleapis.com/auth/service.management.readonly",
    "https://www.googleapis.com/auth/servicecontrol",
    "https://www.googleapis.com/auth/trace.append",
  ]
}

# ---------------------------------------------------------------------------
# Optional hardening.
# ---------------------------------------------------------------------------

variable "database_encryption_key_name" {
  description = "Full resource name of a Cloud KMS key used to encrypt Kubernetes Secrets at the application layer. Leave null to keep Secrets encrypted with the key managed by GKE. Example: projects/acme-apps-prod/locations/us-central1/keyRings/gke/cryptoKeys/apps-prod-us-central1."
  type        = string
  default     = null

  validation {
    condition     = var.database_encryption_key_name == null || can(regex("^projects/[^/]+/locations/[^/]+/keyRings/[^/]+/cryptoKeys/[^/]+$", var.database_encryption_key_name))
    error_message = "database_encryption_key_name must be a Cloud KMS key resource name of the form projects/<project>/locations/<location>/keyRings/<ring>/cryptoKeys/<key>, or null."
  }
}

variable "rbac_security_group" {
  description = "Google group, for example gke-security-groups@example.com, whose members can be granted RBAC roles through group bindings, letting platform engineers administer the cluster with their Google identities. Requires Cloud Identity; GKE requires the group name to start with gke-security-groups@."
  type        = string
  default     = null

  validation {
    condition     = var.rbac_security_group == null || can(regex("^gke-security-groups@[a-zA-Z0-9.-]+$", var.rbac_security_group))
    error_message = "rbac_security_group must be null or a group email starting with gke-security-groups@, for example gke-security-groups@example.com."
  }
}

variable "labels" {
  description = "Labels applied to the cluster resource itself, for example { team = \"platform\", cost-center = \"1234\" }."
  type        = map(string)
  default     = {}

  validation {
    condition     = alltrue([for key, value in var.labels : can(regex("^[a-zA-Z0-9_-]{1,63}$", key)) && can(regex("^[a-zA-Z0-9_-]{0,63}$", value))])
    error_message = "Labels must have keys of 1-63 characters and values of 0-63 characters, using letters, digits, underscores and hyphens."
  }
}
