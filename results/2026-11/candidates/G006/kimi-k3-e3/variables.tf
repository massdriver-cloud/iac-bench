# ============================================================================
# Required inputs — the handful of things an app team must supply.
# Everything else has a default chosen by the platform team.
# ============================================================================

variable "app_name" {
  description = "Short name of the application that owns this storage (e.g. \"orders\"). Used to build the storage account name and the default tags."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,18}[a-z0-9]$", var.app_name))
    error_message = "app_name must be 3-20 characters of lowercase letters, digits and hyphens, starting and ending with a letter or digit."
  }
}

variable "environment" {
  description = "Deployment environment (e.g. \"staging\", \"prod\"). Used in the storage account name and the default tags."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{2,12}$", var.environment))
    error_message = "environment must be 2-12 lowercase letters or digits (e.g. dev, staging, prod)."
  }
}

variable "resource_group_name" {
  description = "Name of the application's existing resource group (e.g. \"orders-staging\"). The storage account is created in it; this module does not create or manage the resource group."
  type        = string

  validation {
    condition     = length(trimspace(var.resource_group_name)) > 0
    error_message = "resource_group_name must not be empty."
  }
}

variable "identity_principal_id" {
  description = <<-EOT
    Object (principal) ID of the application's identity in Entra ID — for a
    user-assigned managed identity this is its Principal ID (NOT the client
    ID). The module grants this identity "Storage Blob Data Contributor" on
    the storage account, so code running on AKS or App Service reads and
    writes blobs with its own identity and never needs an account key.
  EOT
  type        = string

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$", var.identity_principal_id))
    error_message = "identity_principal_id must be a GUID (the identity's object/principal ID, not its client ID)."
  }
}

# ============================================================================
# Optional inputs — sensible defaults already chosen by the platform team.
# ============================================================================

variable "location" {
  description = "Azure region for the storage account. When null (the default), the location of the application's resource group is used."
  type        = string
  default     = null
}

variable "storage_account_name" {
  description = "Explicit storage account name. Leave null to let the module generate a unique, convention-based name (recommended)."
  type        = string
  default     = null

  validation {
    condition     = var.storage_account_name == null || can(regex("^[a-z0-9]{3,24}$", var.storage_account_name))
    error_message = "storage_account_name must be 3-24 characters of lowercase letters and digits (Azure storage naming rules)."
  }
}

variable "containers" {
  description = "Blob containers to create for the application (e.g. [\"uploads\", \"reports\"]). Every container is private; anonymous access is disabled account-wide."
  type        = set(string)
  default     = []

  validation {
    condition = alltrue([
      for c in var.containers :
      can(regex("^[a-z0-9]([a-z0-9-]{1,61}[a-z0-9])?$", c)) && !strcontains(c, "--")
    ])
    error_message = "Container names must be 3-63 characters of lowercase letters, digits and single hyphens, starting and ending with a letter or digit."
  }
}

variable "replication_type" {
  description = "Data redundancy for the account. LRS (default) is cheapest and fine for most environments; consider ZRS for production. Geo options (GRS/RAGRS/GZRS/RAGZRS) add a secondary region."
  type        = string
  default     = "LRS"

  validation {
    condition     = contains(["LRS", "ZRS", "GRS", "RAGRS", "GZRS", "RAGZRS"], var.replication_type)
    error_message = "replication_type must be one of: LRS, ZRS, GRS, RAGRS, GZRS, RAGZRS."
  }
}

variable "access_tier" {
  description = "Default access tier for blobs. Hot (default) is right for active application data such as uploads and generated reports."
  type        = string
  default     = "Hot"

  validation {
    condition     = contains(["Hot", "Cool"], var.access_tier)
    error_message = "access_tier must be Hot or Cool."
  }
}

variable "blob_versioning_enabled" {
  description = "Keep previous versions of blobs automatically. Off by default — soft delete (always on) already covers accidental deletion; turn on when overwrites must also be recoverable."
  type        = bool
  default     = false
}

variable "soft_delete_retention_days" {
  description = "How many days deleted blobs and containers stay recoverable."
  type        = number
  default     = 7

  validation {
    condition     = var.soft_delete_retention_days >= 1 && var.soft_delete_retention_days <= 365
    error_message = "soft_delete_retention_days must be between 1 and 365."
  }
}

variable "lifecycle_rules" {
  description = <<-EOT
    Optional blob lifecycle rules, e.g. to expire re-generatable exports or
    cool down old uploads. Each rule applies to block blobs, optionally
    limited to the given name prefixes, and must have at least one action.
    Example: [{ name = "expire-exports", prefixes = ["reports/"],
    delete_after_days = 90 }]
  EOT
  type = list(object({
    name                       = string
    prefixes                   = optional(list(string), [])
    tier_to_cool_after_days    = optional(number)
    tier_to_archive_after_days = optional(number)
    delete_after_days          = optional(number)
    snapshot_delete_after_days = optional(number)
  }))
  default = []

  validation {
    condition = alltrue([
      for r in var.lifecycle_rules :
      r.tier_to_cool_after_days != null ||
      r.tier_to_archive_after_days != null ||
      r.delete_after_days != null ||
      r.snapshot_delete_after_days != null
    ])
    error_message = "Each lifecycle rule needs at least one action (tier_to_cool_after_days, tier_to_archive_after_days, delete_after_days or snapshot_delete_after_days)."
  }

  validation {
    condition = alltrue([
      for r in var.lifecycle_rules :
      r.tier_to_cool_after_days == null ||
      r.tier_to_archive_after_days == null ||
      r.tier_to_archive_after_days > r.tier_to_cool_after_days
    ])
    error_message = "tier_to_archive_after_days must be greater than tier_to_cool_after_days."
  }
}

variable "shared_access_key_enabled" {
  description = <<-EOT
    Whether the account's shared keys work at all. Applications must use
    their Entra ID identity (the module wires that up) and keys are never
    exported by this module. Keys stay enabled by default for one reason
    only: this module provisions containers over the storage data plane,
    which requires key authentication unless the deploying identity itself
    holds a Storage Blob Data role and the provider uses
    storage_use_azuread. Once your pipeline identity has that, set this to
    false to disable keys entirely.
  EOT
  type        = bool
  default     = true
}

variable "network" {
  description = <<-EOT
    Optional firewall. By default the account accepts HTTPS traffic from
    anywhere — apps on AKS and App Service reach it without network plumbing,
    and data-plane access is still gated by Entra ID RBAC. To lock the
    account down set default_action = "Deny" plus the outbound IPs
    (ip_rules) and/or subnet IDs (subnet_ids) that may reach it.
  EOT
  type = object({
    default_action = optional(string, "Allow")
    ip_rules       = optional(list(string), [])
    subnet_ids     = optional(list(string), [])
  })
  default = {}

  validation {
    condition     = contains(["Allow", "Deny"], var.network.default_action)
    error_message = "network.default_action must be \"Allow\" or \"Deny\"."
  }
}

variable "tags" {
  description = "Extra tags for the storage account. The module always tags with the application name, environment and itself; these are merged on top."
  type        = map(string)
  default     = {}
}
