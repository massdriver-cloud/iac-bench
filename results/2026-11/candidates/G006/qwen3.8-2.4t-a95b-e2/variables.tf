# -----------------------------------------------------------------------------
# Required inputs: the only things an application team normally has to supply.
# -----------------------------------------------------------------------------

variable "application" {
  description = "Name of the application this storage belongs to, e.g. \"orders\". Used to derive the storage account name, default resource group name and tags."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,23}$", var.application))
    error_message = "application must be 3-24 characters, start with a lowercase letter and contain only lowercase letters, digits and hyphens, e.g. \"orders\"."
  }
}

variable "environment" {
  description = "Deployment environment, e.g. \"staging\" or \"prod\". Used in naming, tagging and defaults: environments starting with \"prod\" get zone-redundant (ZRS) replication, all others get LRS."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,15}$", var.environment))
    error_message = "environment must be 3-16 characters, start with a lowercase letter and contain only lowercase letters, digits and hyphens, e.g. \"staging\" or \"prod\"."
  }
}

variable "location" {
  description = "Azure region for the storage account, e.g. \"westeurope\". Casing and spaces are normalised, so \"West Europe\" works too."
  type        = string
}

# -----------------------------------------------------------------------------
# Optional inputs. All have safe defaults - most teams will not set these.
# -----------------------------------------------------------------------------

variable "resource_group_name" {
  description = "Resource group the storage account is placed in. Defaults to \"<application>-<environment>\", the standard per-application resource group, so you normally do not set this."
  type        = string
  default     = null

  validation {
    condition     = var.resource_group_name == null || can(regex("^[a-zA-Z0-9][a-zA-Z0-9-._()]{0,89}$", var.resource_group_name))
    error_message = "resource_group_name must be a valid Azure resource group name (1-90 characters; letters, digits, hyphens, underscores, parentheses and periods)."
  }
}

variable "blob_containers" {
  description = "Blob containers to create for the application's data, e.g. [\"uploads\", \"media\", \"reports\"]. Every container is private; access is granted per identity via Entra ID. Containers are created by the caller's identity over the data plane, so it needs a blob data role on the account (see app_identity_principal_ids)."
  type        = set(string)
  default     = []

  validation {
    condition = alltrue([
      for c in var.blob_containers :
      can(regex("^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$", c))
    ])
    error_message = "Container names must be 3-63 characters of lowercase letters, digits and hyphens, starting and ending with a letter or digit."
  }
}

variable "app_identity_principal_ids" {
  description = "Principal (object) IDs of the application's identities in Entra ID - e.g. the managed identity used on AKS (workload identity) and App Service - that need to read and write blob data. Each is granted the built-in \"Storage Blob Data Contributor\" role on the storage account. Find them under Enterprise applications / Managed identities in the portal, or with `az identity show --query principalId`."
  type        = set(string)
  default     = []

  validation {
    condition = alltrue([
      for id in var.app_identity_principal_ids :
      can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", id))
    ])
    error_message = "Each entry must be a principal (object) ID GUID from Entra ID, e.g. \"1d3f6b2a-9c4e-4b7a-8f2d-6a1c9e5b3d7f\"."
  }
}

variable "replication_type" {
  description = "Override the replication strategy. Leave unset to use the module's default: ZRS (zone-redundant) for production environments, LRS otherwise."
  type        = string
  default     = null

  validation {
    condition     = var.replication_type == null || contains(["LRS", "ZRS", "GRS", "RA-GRS", "GZRS", "RA-GZRS"], var.replication_type)
    error_message = "replication_type must be one of: LRS, ZRS, GRS, RA-GRS, GZRS, RA-GZRS."
  }
}

variable "shared_access_key_enabled" {
  description = "Whether storage account key authorisation is allowed. Default is false: applications authenticate with their Entra ID identity (AKS workload identity / App Service managed identity), and keys cannot be used to access data. Only set this to true if you have a hard dependency on shared keys."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Additional tags to merge with the module's standard tags (application, environment, managed_by)."
  type        = map(string)
  default     = {}
}
