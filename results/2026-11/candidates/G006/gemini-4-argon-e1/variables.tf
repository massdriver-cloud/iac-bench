variable "app_name" {
  description = "Short name of the application (e.g., 'orders'). Used for naming and tagging resources."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,30}[a-z0-9]$", var.app_name))
    error_message = "app_name must be 3-32 characters, lowercase alphanumeric and hyphens, and start/end with an alphanumeric character."
  }
}

variable "environment" {
  description = "Deployment environment name (e.g., 'dev', 'staging', 'prod'). Controls default replication and naming."
  type        = string
  default     = "staging"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.environment))
    error_message = "environment must consist of lowercase alphanumeric characters and hyphens."
  }
}

variable "resource_group_name" {
  description = "Name of the existing resource group where the application's storage account belongs. Defaults to '<app_name>-<environment>' (e.g., 'orders-staging')."
  type        = string
  default     = null
}

variable "location" {
  description = "Azure region for the storage account. If omitted, inherits the location of the application's resource group."
  type        = string
  default     = null
}

variable "principal_id" {
  description = "Entra ID object ID (principal ID) of the application's identity (Managed Identity or Service Principal) to grant Storage Blob Data Contributor access."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.principal_id))
    error_message = "principal_id must be a valid Entra ID Object ID (UUID)."
  }
}

variable "additional_reader_principal_ids" {
  description = "Optional set of additional Entra ID object IDs to grant read-only access (Storage Blob Data Reader) to the storage account."
  type        = set(string)
  default     = []
}

variable "additional_contributor_principal_ids" {
  description = "Optional set of additional Entra ID object IDs to grant read/write access (Storage Blob Data Contributor) to the storage account."
  type        = set(string)
  default     = []
}

variable "containers" {
  description = "Set of private blob container names to create for the application (e.g., ['uploads', 'media', 'exports'])."
  type        = set(string)
  default     = ["uploads", "media", "exports"]

  validation {
    condition = alltrue([
      for c in var.containers : can(regex("^[a-z0-9](?:[a-z0-9-]{1,61}[a-z0-9])?$", c)) && !can(regex("--", c))
    ])
    error_message = "Container names must be 3-63 characters, lowercase letters, numbers, and single hyphens, starting and ending with a letter or number."
  }
}

variable "replication_type" {
  description = "Storage replication type (LRS, ZRS, GRS, GZRS). If null, defaults to ZRS for production environments ('prod'/'production') and LRS for non-production."
  type        = string
  default     = null

  validation {
    condition     = var.replication_type == null || contains(["LRS", "ZRS", "GRS", "GZRS", "RAGRS", "RAGZRS"], coalesce(var.replication_type, "LRS"))
    error_message = "replication_type must be one of LRS, ZRS, GRS, GZRS, RAGRS, RAGZRS, or null."
  }
}

variable "soft_delete_retention_days" {
  description = "Number of days to retain soft-deleted blobs, versions, and containers for recovery from accidental deletion."
  type        = number
  default     = 14

  validation {
    condition     = var.soft_delete_retention_days >= 1 && var.soft_delete_retention_days <= 365
    error_message = "soft_delete_retention_days must be between 1 and 365."
  }
}

variable "enable_versioning" {
  description = "Enable automatic blob versioning to protect against accidental overwrites."
  type        = bool
  default     = true
}

variable "auto_cool_after_days" {
  description = "Days since last modification before blobs automatically transition to Cool storage tier."
  type        = number
  default     = 30

  validation {
    condition     = var.auto_cool_after_days >= 1
    error_message = "auto_cool_after_days must be at least 1 day."
  }
}

variable "delete_old_versions_after_days" {
  description = "Days after creation before non-current blob versions are automatically expired to control storage costs."
  type        = number
  default     = 90

  validation {
    condition     = var.delete_old_versions_after_days >= 1
    error_message = "delete_old_versions_after_days must be at least 1 day."
  }
}

variable "cors_allowed_origins" {
  description = "Optional list of allowed origins (e.g., ['https://orders.example.com']) for browser direct-to-blob uploads/downloads via CORS."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Additional tags to apply to the storage account. Merged with standard application, environment, and existing resource group tags."
  type        = map(string)
  default     = {}
}
