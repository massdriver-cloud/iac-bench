# =============================================================================
# Required: the per-cluster facts the platform team must supply.
# Everything below this section has a production default.
# =============================================================================

variable "project_id" {
  description = "The Google Cloud project that hosts the environment's VPC. The cluster, its node identity and all IAM bindings are created in this same project."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "project_id must be a Google Cloud project id: 6-30 lowercase letters, digits and hyphens, starting with a letter."
  }
}

variable "name" {
  description = "Short cluster name, unique within the project. Also forms the node service account id (gke-<name>-nodes), so it must stay at or below 20 characters."
  type        = string

  validation {
    condition     = can(regex("^[a-z]([-a-z0-9]{0,18}[a-z0-9])?$", var.name))
    error_message = "name must be at most 20 characters of lowercase letters, digits and hyphens, must start with a lowercase letter and must not end with a hyphen (the derived node service account id is limited to 30 characters)."
  }
}

variable "region" {
  description = "US region for the cluster, e.g. us-central1, us-east4, us-west2. The network team has an apps-<environment>-gke-<region> subnet in each of the team's US regions."
  type        = string

  validation {
    condition     = can(regex("^us-[a-z]+[0-9]+$", var.region))
    error_message = "region must be a US region such as us-central1 or us-east4; the standard GKE subnets only exist in US regions."
  }
}

variable "environment" {
  description = "Environment of the cluster. Selects the network team's VPC apps-<environment> and its GKE subnet apps-<environment>-gke-<region>. Known environments today: staging, prod."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,20}$", var.environment))
    error_message = "environment must be 1-21 characters of lowercase letters, digits and hyphens (e.g. staging or prod)."
  }
}

variable "master_authorized_networks" {
  description = "CIDR ranges allowed to reach the Kubernetes API server's endpoint, as a map of display name to CIDR, e.g. { platform-vpn = \"203.0.113.0/24\" }. Supply the ranges platform engineers actually connect from (VPN, office, CI). The cluster's private nodes always reach the control plane privately, regardless of this list."
  type        = map(string)

  validation {
    condition     = length(var.master_authorized_networks) > 0
    error_message = "master_authorized_networks cannot be empty: without it the control plane endpoint is reachable from the whole internet."
  }

  validation {
    condition     = alltrue([for cidr in values(var.master_authorized_networks) : can(cidrnetmask(cidr))])
    error_message = "every value of master_authorized_networks must be a valid IPv4 CIDR block such as 203.0.113.0/24."
  }

  validation {
    condition     = alltrue([for cidr in values(var.master_authorized_networks) : cidr != "0.0.0.0/0"])
    error_message = "0.0.0.0/0 would allow the entire internet to reach the control plane endpoint."
  }
}

# =============================================================================
# Node pools
# =============================================================================

variable "node_pools" {
  description = <<-EOT
    Node pools for the cluster, keyed by pool name. Each entry becomes a
    managed, autoscaling node pool, and every pool gets a node label
    pool = <pool name> that teams can select on with nodeSelector/affinity.
    Fields (all optional):

      machine_type       default c3-standard-4 (4 vCPU / 16 GB)
      min_count          autoscaler floor, PER ZONE, default 2 (=> 6 nodes on a regional cluster)
      max_count          autoscaler ceiling, per zone, default 10
      disk_size_gb       node boot disk size, default 100
      disk_type          default pd-balanced
      image_type         default COS_CONTAINERD
      spot / preemptible default false; use them for stateless/batch pools only
      node_locations     zones for this pool; null = every zone in the region
      max_pods_per_node  default null = GKE default (110)
      labels             extra GKE node labels, merged with the module's

    The default "general" pool suits a shared general-purpose cluster. Product
    teams needing dedicated capacity get their own entry.
  EOT
  type = map(object({
    machine_type      = optional(string, "c3-standard-4")
    min_count         = optional(number, 2)
    max_count         = optional(number, 10)
    disk_size_gb      = optional(number, 100)
    disk_type         = optional(string, "pd-balanced")
    image_type        = optional(string, "COS_CONTAINERD")
    spot              = optional(bool, false)
    preemptible       = optional(bool, false)
    node_locations    = optional(list(string))
    max_pods_per_node = optional(number)
    labels            = optional(map(string), {})
  }))

  default = {
    general = {
      machine_type = "c3-standard-4"
      min_count    = 2
      max_count    = 10
    }
  }

  validation {
    condition     = alltrue([for pool_name in keys(var.node_pools) : can(regex("^[a-z0-9]([-a-z0-9]{0,38}[a-z0-9])?$", pool_name))])
    error_message = "node pool names (the map keys) must be 1-40 characters of lowercase letters, digits and hyphens, and must not start or end with a hyphen."
  }

  validation {
    condition     = alltrue([for pool in values(var.node_pools) : pool.min_count >= 1 && pool.min_count <= pool.max_count])
    error_message = "every node pool needs min_count >= 1 and min_count <= max_count."
  }

  validation {
    condition     = alltrue([for pool in values(var.node_pools) : !(pool.spot && pool.preemptible)])
    error_message = "a node pool can be spot or preemptible, not both."
  }

  validation {
    condition = alltrue([
      for pool in values(var.node_pools) :
      alltrue([
        for zone in(pool.node_locations == null ? [] : pool.node_locations) :
        can(regex("^us-[a-z]+[0-9]+-[a-z]$", zone))
      ])
    ])
    error_message = "node_locations must be zones (not regions) in the cluster's region, e.g. [\"us-central1-a\"]."
  }

  validation {
    condition = alltrue([
      for pool in values(var.node_pools) :
      alltrue([for key, value in pool.labels : can(regex("^[a-z0-9_-]{0,63}$", key)) && can(regex("^[a-z0-9_-]{0,63}$", value))])
    ])
    error_message = "node pool label keys and values must be at most 63 characters of lowercase letters, digits, hyphens and underscores."
  }
}

# =============================================================================
# Control plane exposure and versioning
# =============================================================================

variable "enable_private_endpoint" {
  description = "Set true to remove the control plane's public endpoint entirely; the API server is then reachable only via its private IP in the VPC (global access is enabled). Default false: a public endpoint restricted to master_authorized_networks, which is what engineers use from the VPN or office. Nodes are private either way."
  type        = bool
  default     = false
}

variable "master_ipv4_cidr_block" {
  description = "The /28 for the control plane's private endpoint. null (default) lets GKE pick a free /28 in the VPC. Set it only to keep control plane ranges documented or to guarantee uniqueness across several clusters in the same VPC."
  type        = string
  default     = null

  validation {
    condition     = var.master_ipv4_cidr_block == null || (can(cidrnetmask(var.master_ipv4_cidr_block)) && endswith(var.master_ipv4_cidr_block, "/28"))
    error_message = "master_ipv4_cidr_block must be an IPv4 /28, e.g. 172.16.8.0/28."
  }
}

variable "release_channel" {
  description = "GKE release channel: REGULAR (default) is the production channel; RAPID tracks the newest Kubernetes and is a reasonable choice for staging; STABLE lags the furthest. The module never pins Kubernetes versions: the channel decides, and upgrades happen inside the maintenance window."
  type        = string
  default     = "REGULAR"

  validation {
    condition     = contains(["RAPID", "REGULAR", "STABLE"], var.release_channel)
    error_message = "release_channel must be RAPID, REGULAR or STABLE."
  }
}

# =============================================================================
# Security extras
# =============================================================================

variable "authenticator_security_group" {
  description = "Google Group used by RBAC Google Groups for GKE, e.g. gke-security-groups@example.com. Members of that group (or groups nested in it) can be granted cluster-admin via RBAC group bindings instead of per-user bindings. null (default) disables the integration."
  type        = string
  default     = null

  validation {
    condition     = var.authenticator_security_group == null || startswith(var.authenticator_security_group, "gke-security-groups@")
    error_message = "the group for RBAC Google Groups must be named gke-security-groups@<domain>; Google enforces this prefix."
  }
}

variable "database_encryption_kms_key" {
  description = "Self link of a Cloud KMS key used to encrypt Kubernetes Secrets at rest, e.g. projects/<project>/locations/us-central1/keyRings/gke/cryptoKeys/<cluster>. The key ring must live in the cluster's region. null (default) keeps Google-managed encryption."
  type        = string
  default     = null
}

variable "enable_network_policy" {
  description = "Enforce Kubernetes NetworkPolicy so product-team namespaces can isolate themselves from each other. Default true."
  type        = bool
  default     = true
}

variable "enable_gateway_api" {
  description = "Enable the Gateway API (GA channel) so each product team can own its ingress instead of annotating a shared LoadBalancer Service. Default true."
  type        = bool
  default     = true
}

variable "deletion_protection" {
  description = "Protect the cluster against accidental deletion (tofu destroy). Production clusters are protected by default. To decommission a cluster on purpose, set this to false, apply, then destroy."
  type        = bool
  default     = true
}

# =============================================================================
# Workload identity
# =============================================================================

variable "workload_identity_bindings" {
  description = "Workload Identity bindings: a Kubernetes service account is allowed to impersonate a Google service account, so its Pods can use Pub/Sub, Cloud Storage, Cloud SQL and other Google services without keys. The Google service account must already exist in project_id. Example: { payments = { google_service_account = \"payments@<project>.iam.gserviceaccount.com\", namespace = \"payments\", kubernetes_service_account = \"publisher\" } }."
  type = map(object({
    google_service_account     = string
    namespace                  = string
    kubernetes_service_account = string
  }))
  default = {}

  validation {
    condition = alltrue([
      for binding in values(var.workload_identity_bindings) :
      endswith(binding.google_service_account, ".iam.gserviceaccount.com")
    ])
    error_message = "google_service_account must be a service account email ending in .iam.gserviceaccount.com."
  }

  validation {
    condition = alltrue([
      for binding in values(var.workload_identity_bindings) :
      can(regex("^[a-z0-9]([-a-z0-9]{0,61}[a-z0-9])?$", binding.namespace)) &&
      can(regex("^[a-z0-9]([-a-z0-9]{0,61}[a-z0-9])?$", binding.kubernetes_service_account))
    ])
    error_message = "namespace and kubernetes_service_account must be valid Kubernetes names (lowercase alphanumeric with internal hyphens)."
  }
}

# =============================================================================
# Everything else
# =============================================================================

variable "maintenance_window" {
  description = "The weekly maintenance window, in UTC. GKE performs disruptive control plane maintenance only inside it, and node upgrades prefer it. Defaults to Saturday 09:00-13:00 UTC, which is early morning on both US coasts."
  type = object({
    day            = optional(string, "SAT")
    start_hour_utc = optional(number, 9)
    duration_hours = optional(number, 4)
  })
  default = {}

  validation {
    condition     = contains(["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"], var.maintenance_window.day)
    error_message = "maintenance_window.day must be a three-letter uppercase weekday, e.g. SAT."
  }

  validation {
    condition     = var.maintenance_window.start_hour_utc >= 0 && var.maintenance_window.start_hour_utc <= 23
    error_message = "maintenance_window.start_hour_utc must be an hour of the day, 0-23."
  }

  validation {
    condition     = var.maintenance_window.duration_hours >= 4 && var.maintenance_window.duration_hours <= 24
    error_message = "maintenance_window.duration_hours must be between 4 and 24 hours."
  }

  validation {
    condition     = var.maintenance_window.start_hour_utc + var.maintenance_window.duration_hours <= 24
    error_message = "the maintenance window must end on the same UTC day it starts; choose start_hour_utc and duration_hours accordingly."
  }
}

variable "labels" {
  description = "Extra labels applied to the cluster and every node pool, merged over the module's own labels (environment, managed-by; node pools also carry pool)."
  type        = map(string)
  default     = {}

  validation {
    condition     = alltrue([for key, value in var.labels : can(regex("^[a-z0-9_-]{1,63}$", key)) && can(regex("^[a-z0-9_-]{0,63}$", value))])
    error_message = "label keys and values must be at most 63 characters of lowercase letters, digits, hyphens and underscores."
  }
}

variable "additional_node_service_account_roles" {
  description = "Extra project-level IAM roles granted to the cluster's node service account, for legacy workloads that are not on Workload Identity yet. Avoid this for new access; wire workload_identity_bindings instead."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for role in var.additional_node_service_account_roles : startswith(role, "roles/")])
    error_message = "roles must be Google IAM roles such as roles/pubsub.subscriber."
  }
}
