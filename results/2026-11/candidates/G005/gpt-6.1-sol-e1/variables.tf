variable "project_id" {
  description = "Existing Google Cloud project containing both the cluster and environment VPC."
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "Supply a Google Cloud project ID, not a project number."
  }
}

variable "cluster_name" {
  description = "Unique cluster name within the project and region."
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,38}[a-z0-9]$", var.cluster_name))
    error_message = "Use 2-40 lowercase letters, digits or hyphens, starting with a letter and ending with a letter or digit."
  }
}

variable "environment" {
  description = "Selects the existing apps-staging or apps-prod VPC."
  type        = string
  validation {
    condition     = contains(["staging", "prod"], var.environment)
    error_message = "environment must be staging or prod."
  }
}

variable "region" {
  description = "US region containing the existing <vpc>-gke-<region> subnet, with at least three available zones."
  type        = string
  validation {
    condition     = can(regex("^us-[a-z]+[0-9]+$", var.region))
    error_message = "Use a US region, for example us-central1."
  }
}

variable "master_ipv4_cidr_block" {
  description = "Unique RFC1918 /28 reserved for this cluster's control plane; must not overlap any connected subnet, secondary range, peer or other control plane. Coordinate with the network team."
  type        = string
  validation {
    condition = can(cidrhost(var.master_ipv4_cidr_block, 0)) && can(regex("/28$", var.master_ipv4_cidr_block)) && (
      can(regex("^10\\.", var.master_ipv4_cidr_block)) ||
      can(regex("^192\\.168\\.", var.master_ipv4_cidr_block)) ||
      can(regex("^172\\.(1[6-9]|2[0-9]|3[01])\\.", var.master_ipv4_cidr_block))
    )
    error_message = "Use an RFC1918 IPv4 /28 CIDR reserved for this cluster."
  }
}

variable "control_plane_authorized_cidrs" {
  description = "Private runner, VPN or bastion CIDRs permitted to access the private Kubernetes API. No public endpoint is created."
  type        = map(string)
  validation {
    condition = length(var.control_plane_authorized_cidrs) > 0 && alltrue([
      for cidr in values(var.control_plane_authorized_cidrs) :
      can(cidrnetmask(cidr)) && try(tonumber(split("/", cidr)[1]) >= 8, false) && (
        can(regex("^10\\.", cidr)) || can(regex("^192\\.168\\.", cidr)) || can(regex("^172\\.(1[6-9]|2[0-9]|3[01])\\.", cidr))
      )
    ])
    error_message = "Supply at least one named RFC1918 IPv4 CIDR, /8 or narrower; the API is private-only."
  }
}

variable "node_pools" {
  description = "Node pools distributed across exactly three zones. Autoscaling limits are PER ZONE (three times these counts cluster-wide). Keep enough capacity for a zone failure and system workloads. All pools use on-demand nodes."
  type = map(object({
    machine_type       = optional(string, "e2-standard-4")
    min_nodes_per_zone = optional(number, 1)
    max_nodes_per_zone = optional(number, 3)
    disk_size_gb       = optional(number, 100)
    labels             = optional(map(string), {})
  }))
  default = { general = {} }
  validation {
    condition = length(var.node_pools) > 0 && alltrue([
      for name, pool in var.node_pools :
      can(regex("^[a-z][a-z0-9-]{0,38}[a-z0-9]$", name)) &&
      pool.min_nodes_per_zone >= 1 && floor(pool.min_nodes_per_zone) == pool.min_nodes_per_zone &&
      pool.max_nodes_per_zone >= pool.min_nodes_per_zone && floor(pool.max_nodes_per_zone) == pool.max_nodes_per_zone &&
      pool.disk_size_gb >= 100 && floor(pool.disk_size_gb) == pool.disk_size_gb
    ])
    error_message = "Supply named pools (2-40 lowercase characters) with integer minimum >= 1, maximum >= minimum and disks >= 100 GiB."
  }
}

variable "deletion_protection" {
  description = "Protect against accidental deletion. Set false and apply before intentionally destroying the cluster."
  type        = bool
  default     = true
}

variable "workload_identities" {
  description = "Optional GCP service accounts for Kubernetes workloads. Module grants Workload Identity impersonation and explicitly requested project roles. Create/annotate the Kubernetes ServiceAccount separately; use resource-level IAM instead of project_roles where possible."
  type = map(object({
    namespace                  = string
    kubernetes_service_account = string
    project_roles              = optional(set(string), [])
  }))
  default = {}
  validation {
    condition = alltrue([
      for identity in values(var.workload_identities) :
      can(regex("^[a-z0-9]([-a-z0-9]{0,61}[a-z0-9])?$", identity.namespace)) &&
      can(regex("^[a-z0-9]([-a-z0-9]{0,61}[a-z0-9])?$", identity.kubernetes_service_account)) &&
      alltrue([for role in identity.project_roles : !contains(["roles/owner", "roles/editor", "roles/viewer"], role)])
    ])
    error_message = "Use valid Kubernetes namespace/service account names and granular IAM roles, not basic owner/editor/viewer roles."
  }
}
