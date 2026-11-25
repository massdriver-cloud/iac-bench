# ---------------------------------------------------------------------------
# Required inputs - the only things an app team must decide.
# ---------------------------------------------------------------------------

variable "app_name" {
  description = "Short name of the application that owns this storage (e.g. \"orders\"). Lowercase letters, digits and hyphens; 2-20 characters. Used for naming and tagging."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,18}[a-z0-9]$", var.app_name))
    error_message = "app_name must be 2-20 characters, lowercase letters/digits/hyphens, starting with a letter and ending with a letter or digit."
  }
}

variable "environment" {
  description = "Environment this storage belongs to (e.g. \"dev\", \"staging\", \"prod\"). Lowercase letters and digits, up to 10 characters. \"prod\" gets zone-redundant storage and longer soft-delete retention."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{1,10}$", var.environment))
    error_message = "environment must be 1-10 lowercase letters or digits (e.g. dev, staging, prod)."
  }
}

variable "resource_group_name" {
  description = "Name of the application's existing resource group for this environment (e.g. \"orders-staging\"). The storage account is created inside it; the group is never created or modified by this module."
  type        = string

  validation {
    condition     = length(var.resource_group_name) > 0
    error_message = "resource_group_name must not be empty."
  }
}

variable "location" {
  description = "Azure region for the storage account (e.g. \"westeurope\"). Use the same region as the application's resource group."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]+$", var.location))
    error_message = "location must be an Azure region name such as \"westeurope\" (lowercase, no spaces)."
  }
}

# ---------------------------------------------------------------------------
# Optional inputs - safe defaults are provided; most teams never touch these.
# ---------------------------------------------------------------------------

variable "containers" {
  description = "Blob containers to create for the application's files (e.g. [\"uploads\", \"reports\"]). All containers are private; access is via the application's Entra ID identity, never anonymous."
  type        = set(string)
  default     = []

  validation {
    condition = alltrue([
      for c in var.containers : can(regex("^[a-z0-9]([a-z0-9-]{1,61}[a-z0-9])?$", c)) && !can(regex("--", c))
    ])
    error_message = "Container names must be 3-63 characters of lowercase letters, digits or single hyphens, starting and ending with a letter or digit."
  }
}

variable "application_principal_ids" {
  description = "Entra ID object (principal) IDs of the application's identities (AKS workload identity / App Service managed identity). Each is granted \"Storage Blob Data Contributor\" on this account. This is the only supported way for the app to read/write data - storage account keys are disabled."
  type        = set(string)
  default     = []

  validation {
    condition     = alltrue([for p in var.application_principal_ids : can(regex("^[0-9a-fA-F-]{36}$", p))])
    error_message = "Each principal ID must be a GUID (the identity's object ID, not its client/app ID)."
  }
}

variable "replication_type" {
  description = "Override the redundancy strategy. Leave null to use the module default: ZRS (zone-redundant) for prod, LRS for non-prod."
  type        = string
  default     = null

  validation {
    condition     = var.replication_type == null || contains(["LRS", "ZRS", "GRS", "RAGRS", "GZRS", "RAGZRS"], var.replication_type)
    error_message = "replication_type must be one of LRS, ZRS, GRS, RAGRS, GZRS, RAGZRS (or null for the module default)."
  }
}

variable "soft_delete_retention_days" {
  description = "Override how many days deleted blobs/containers can be recovered. Leave null for the module default: 14 days for prod, 7 days otherwise."
  type        = number
  default     = null

  validation {
    condition     = var.soft_delete_retention_days == null || (var.soft_delete_retention_days >= 1 && var.soft_delete_retention_days <= 365)
    error_message = "soft_delete_retention_days must be between 1 and 365 (or null for the module default)."
  }
}

variable "storage_account_name_override" {
  description = "Escape hatch for an exact storage account name (must be globally unique, 3-24 lowercase letters/digits). Leave null and the module generates a safe, unique name from app_name + environment."
  type        = string
  default     = null

  validation {
    condition     = var.storage_account_name_override == null || can(regex("^[a-z0-9]{3,24}$", var.storage_account_name_override))
    error_message = "storage_account_name_override must be 3-24 lowercase letters and digits only."
  }
}

variable "tags" {
  description = "Extra tags to apply to all resources. The module always adds app, environment and managed-by tags."
  type        = map(string)
  default     = {}
}

variable "subscription_id" {
  description = "Azure subscription ID. Leave null to use the subscription from the environment (ARM_SUBSCRIPTION_ID)."
  type        = string
  default     = null
}
