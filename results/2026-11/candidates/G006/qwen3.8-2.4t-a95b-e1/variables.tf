# -----------------------------------------------------------------------------
# Inputs we expect application teams to fill in.
#
# A minimal call of this module looks like:
#
#   module "orders_staging_storage" {
#     source = "<this module>"
#
#     application_name           = "orders"
#     environment                = "staging"
#     location                   = "westeurope"
#     app_identity_principal_ids = ["<object ID of the app's Entra ID identity>"]
#   }
#
# Everything else has an opinionated, documented default (see README.md).
# -----------------------------------------------------------------------------

variable "application_name" {
  type        = string
  description = "Name of the application that owns this storage, e.g. \"orders\". Used for naming, tags, and the default resource group name."

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,29}$", var.application_name))
    error_message = "application_name must be 2-30 characters: lowercase letters, digits and hyphens, starting with a letter."
  }
}

variable "environment" {
  type        = string
  description = "Environment this storage belongs to, e.g. \"staging\" or \"prod\". Used for naming, tags, and the default resource group name."

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,14}$", var.environment))
    error_message = "environment must be 2-15 characters: lowercase letters, digits and hyphens, starting with a letter."
  }
}

variable "location" {
  type        = string
  description = "Azure region for the storage account, e.g. \"westeurope\". Pick the region your application runs in so data calls stay fast and cheap."
}

variable "resource_group_name" {
  type        = string
  default     = null
  description = "The application's existing resource group to place the storage account in. Defaults to \"<application_name>-<environment>\" (e.g. \"orders-staging\"), our standard per-app, per-environment layout. Only set this if your resource group is named differently."
}

variable "app_identity_principal_ids" {
  type        = list(string)
  description = "Object (principal) IDs of the application's identities in Entra ID - for example its AKS workload identity and/or its App Service managed identity. These identities are granted Storage Blob Data Contributor on the account, which is how the app reads and writes blobs (no connection strings, no account keys)."

  validation {
    condition     = length(var.app_identity_principal_ids) > 0
    error_message = "Provide at least one application identity principal ID - without it the app cannot reach its storage."
  }

  validation {
    condition = alltrue([
      for id in var.app_identity_principal_ids :
      can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", id))
    ])
    error_message = "Every entry must be a GUID - the object (principal) ID of an identity in Entra ID."
  }
}

variable "containers" {
  type        = set(string)
  default     = ["media", "reports", "uploads"]
  description = "Blob containers to create. The default is the standard layout: \"uploads\" for user uploads, \"media\" for images and videos, \"reports\" for generated reports and exports. Override with your own list only if your app needs different containers."

  validation {
    condition = alltrue([
      for name in var.containers :
      can(regex("^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$", name))
    ])
    error_message = "Container names must be 3-63 characters: lowercase letters, digits and hyphens, starting and ending with a letter or digit."
  }
}

variable "replication_type" {
  type        = string
  default     = "LRS"
  description = "How Azure replicates the data. Default is LRS (locally redundant), the sensible baseline for application data. Choose ZRS if you cannot tolerate a datacenter zone outage, GRS/RA-GRS/GZRS/RA-GZRS for cross-region copies. Most app teams should leave this alone."

  validation {
    condition     = contains(["LRS", "ZRS", "GRS", "GZRS", "RA-GRS", "RA-GZRS"], var.replication_type)
    error_message = "replication_type must be one of: LRS, ZRS, GRS, GZRS, RA-GRS, RA-GZRS."
  }
}

variable "storage_account_name" {
  type        = string
  default     = null
  description = "Override for the storage account name. By default the name is derived from the application and environment names (e.g. \"ordersstaging\"), which is deterministic and needs no extra input. Only set this if the derived name is taken or you need a specific name."

  validation {
    condition     = var.storage_account_name == null || can(regex("^[a-z0-9]{3,24}$", var.storage_account_name))
    error_message = "storage_account_name must be 3-24 lowercase alphanumeric characters (Azure's rules for storage account names)."
  }
}

variable "enable_reports_lifecycle_policy" {
  type        = bool
  default     = true
  description = "Whether to move blobs in the \"reports\" container to the cool tier after 30 days and to the archive tier after 120 days. Generated reports and exports are usually read once and then rarely touched, so this saves money. Set to false if your app needs reports to stay hot."
}

variable "extra_tags" {
  type        = map(string)
  default     = {}
  description = "Additional tags to apply on top of the standard tags (application, environment, managed_by, module). On conflicts your value wins."
}
