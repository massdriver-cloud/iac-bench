# ---------------------------------------------------------------------------
# The obvious inputs
# ---------------------------------------------------------------------------

variable "application" {
  type        = string
  description = <<-EOT
    Name of the application this storage belongs to, e.g. "orders".
    Used for naming and tagging. You normally don't need anything else.
  EOT

  validation {
    condition     = can(regex("^[A-Za-z][A-Za-z0-9-]{0,29}$", var.application))
    error_message = "application must start with a letter and contain only letters, digits and hyphens (max 30 chars), e.g. \"orders\"."
  }
}

variable "environment" {
  type        = string
  description = <<-EOT
    Deployment environment, e.g. "staging" or "prod".
    Used for naming and tagging.
  EOT

  validation {
    condition     = can(regex("^[A-Za-z][A-Za-z0-9-]{0,14}$", var.environment))
    error_message = "environment must start with a letter and contain only letters, digits and hyphens (max 15 chars), e.g. \"staging\" or \"prod\"."
  }
}

variable "resource_group_name" {
  type        = string
  default     = null
  description = <<-EOT
    The application's existing resource group, e.g. "orders-staging".
    Storage is placed there. If you leave this unset the module creates the
    conventional "<application>-<environment>" resource group instead
    (then `location` is required).
  EOT

  validation {
    condition     = var.resource_group_name == null || can(regex("^[-\\w._()]{1,89}[-\\w._()]$", var.resource_group_name))
    error_message = "resource_group_name must be a valid Azure resource group name (1-90 chars: letters, digits, hyphen, underscore, period, parentheses)."
  }
}

variable "location" {
  type        = string
  default     = null
  description = <<-EOT
    Azure region, e.g. "westeurope".
    Leave unset to inherit the region of the application's resource group.
    Required only when the module also creates the resource group.
  EOT
}

# ---------------------------------------------------------------------------
# What the application stores
# ---------------------------------------------------------------------------

variable "blob_containers" {
  type        = set(string)
  default     = []
  description = <<-EOT
    Blob containers to create for the application, e.g. ["uploads", "exports"].
    Blobs are the right home for user uploads, images, videos, reports.
    Containers are always private; apps read/write them with their identity.
  EOT

  validation {
    condition     = alltrue([for n in var.blob_containers : can(regex("^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$", n))])
    error_message = "Container names must be 3-63 characters of lowercase letters, digits and hyphens, and must not start or end with a hyphen."
  }
}

variable "queues" {
  type        = set(string)
  default     = []
  description = <<-EOT
    Storage queues to create for background/work messages, e.g. ["thumbnail-jobs"].
    Leave empty if the application does not use queues.
  EOT

  validation {
    condition     = alltrue([for n in var.queues : can(regex("^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$", n))])
    error_message = "Queue names must be 3-63 characters of lowercase letters, digits and hyphens, and must not start or end with a hyphen."
  }
}

variable "file_shares" {
  type        = set(string)
  default     = []
  description = <<-EOT
    Azure Files SMB shares to create, e.g. ["batch-spool"].
    Leave empty unless the application genuinely needs mountable file shares;
    most application files belong in blob containers.
  EOT

  validation {
    condition     = alltrue([for n in var.file_shares : can(regex("^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$", n))])
    error_message = "Share names must be 3-63 characters of lowercase letters, digits and hyphens, and must not start or end with a hyphen."
  }
}

# ---------------------------------------------------------------------------
# Who may access the data
# ---------------------------------------------------------------------------

variable "app_identity_object_ids" {
  type        = list(string)
  default     = []
  description = <<-EOT
    Object (principal) IDs of the application's Entra ID identities, e.g. the
    managed identities used on AKS and App Service. The module grants each of
    them data access with built-in roles: "Storage Blob Data Contributor",
    plus "Storage Queue Data Contributor" and
    "Storage File Data SMB Share Contributor" when queues/shares are in use.
  EOT

  validation {
    condition     = alltrue([for id in var.app_identity_object_ids : can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", id))])
    error_message = "app_identity_object_ids must be Entra ID object IDs (GUIDs), e.g. \"3f2c8a1e-9b4d-4a6e-8c1f-0d5e7a9b2c34\"."
  }
}

# ---------------------------------------------------------------------------
# Networking
# ---------------------------------------------------------------------------

variable "private_endpoint_subnet_id" {
  type        = string
  default     = null
  description = <<-EOT
    Subnet (in the same region) where the application runs, e.g. the AKS or
    App Service delegated subnet. When set, the module creates private
    endpoints so the app reaches storage privately. Leave unset while you have
    no VNet; the account stays reachable by no one until you wire this up.
  EOT
}

variable "private_dns_zone_ids" {
  type        = map(string)
  default     = {}
  description = <<-EOT
    Optional private DNS zones for the private endpoints, keyed by service:
    { blob = "/subscriptions/.../privateDnsZones/privatelink.blob.core.windows.net",
      file = ".../privatelink.file.core.windows.net", queue = "..." }.
    Leave empty if your platform team resolves privatelink DNS centrally.
  EOT
}

variable "public_network_access_enabled" {
  type        = bool
  default     = false
  description = <<-EOT
    The module's judgment is "no internet exposure": apps on AKS/App Service
    reach storage over private endpoints (or VNet service endpoints). Only set
    this true with `allowed_subnet_ids` if you have a concrete reason.
  EOT
}

variable "allowed_subnet_ids" {
  type        = list(string)
  default     = []
  description = <<-EOT
    Subnets allowed through the storage firewall via service endpoints.
    Only relevant when public_network_access_enabled is true.
  EOT
}

# ---------------------------------------------------------------------------
# Rarely-touched defaults (the module's judgment, overridable with a reason)
# ---------------------------------------------------------------------------

variable "replication_type" {
  type        = string
  default     = "LRS"
  description = <<-EOT
    Redundancy. LRS (three replicas in one region) is the standard, cheapest
    durable choice for application data. Use ZRS/GZRS only when your
    availability requirements genuinely demand cross-zone/region replicas.
  EOT

  validation {
    condition     = contains(["LRS", "ZRS", "GRS", "RAGRS", "GZRS", "RAGZRS"], var.replication_type)
    error_message = "replication_type must be one of: LRS, ZRS, GRS, RAGRS, GZRS, RAGZRS."
  }
}

variable "blob_versioning_enabled" {
  type        = bool
  default     = true
  description = <<-EOT
    Keep previous versions of blobs so accidental overwrites are recoverable.
    Turn off only for data that is cheap to regenerate and cost-sensitive.
  EOT
}

variable "shared_access_key_enabled" {
  type        = bool
  default     = false
  description = <<-EOT
    Shared keys (and SAS tokens) are disabled by default: applications
    authenticate with their Entra ID identity instead, so there is no secret
    to leak or rotate. Enable only for a legacy requirement (SAS URLs,
    key-based mounts) and plan to turn it off again.
  EOT
}

variable "additional_tags" {
  type        = map(string)
  default     = {}
  description = "Extra tags to add to every resource. Standard tags (application, environment, module, managed-by) are always applied."
}
