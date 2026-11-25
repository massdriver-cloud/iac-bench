variable "name" {
  description = "Application name used for resource naming and tags. It is normalized before being used in the storage account name."
  type        = string

  validation {
    condition     = length(var.name) > 0 && length(var.name) <= 20
    error_message = "name must be between 1 and 20 characters long."
  }

  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9-]*$", var.name))
    error_message = "name must start with a letter or number and contain only letters, numbers, and hyphens."
  }
}

variable "environment" {
  description = "Environment name, for example staging or prod. Used for naming and tags."
  type        = string

  validation {
    condition     = length(var.environment) > 0 && length(var.environment) <= 12
    error_message = "environment must be between 1 and 12 characters long."
  }

  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9-]*$", var.environment))
    error_message = "environment must start with a letter or number and contain only letters, numbers, and hyphens."
  }
}

variable "resource_group_name" {
  description = "Name of the existing resource group where the application's storage belongs."
  type        = string

  validation {
    condition     = length(var.resource_group_name) > 0
    error_message = "resource_group_name must not be empty."
  }
}

variable "location" {
  description = "Azure region for the storage account, for example eastus."
  type        = string

  validation {
    condition     = length(var.location) > 0
    error_message = "location must not be empty."
  }
}

variable "identity_principal_id" {
  description = "Object ID of the application's Entra ID identity (managed identity or service principal) that will be granted blob data access."
  type        = string

  validation {
    condition     = length(var.identity_principal_id) > 0
    error_message = "identity_principal_id must not be empty."
  }
}

variable "storage_account_name" {
  description = "Optional explicit storage account name. If omitted, the module derives a globally unique-friendly lowercase name from the application, environment, resource group, and location."
  type        = string
  default     = null

  validation {
    condition = var.storage_account_name == null || (
      length(var.storage_account_name) >= 3 &&
      length(var.storage_account_name) <= 24 &&
      can(regex("^[a-z0-9]+$", var.storage_account_name))
    )
    error_message = "storage_account_name, when set, must be 3-24 lowercase letters or numbers with no hyphens."
  }
}

variable "account_tier" {
  description = "Storage account tier."
  type        = string
  default     = "Standard"

  validation {
    condition     = contains(["Standard", "Premium"], var.account_tier)
    error_message = "account_tier must be Standard or Premium."
  }
}

variable "account_replication_type" {
  description = "Storage account replication type."
  type        = string
  default     = "LRS"

  validation {
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"], var.account_replication_type)
    error_message = "account_replication_type must be one of LRS, GRS, RAGRS, ZRS, GZRS, RAGZRS."
  }
}

variable "account_kind" {
  description = "Storage account kind."
  type        = string
  default     = "StorageV2"

  validation {
    condition     = contains(["StorageV2", "Storage", "BlobStorage", "BlockBlobStorage", "FileStorage"], var.account_kind)
    error_message = "account_kind must be one of StorageV2, Storage, BlobStorage, BlockBlobStorage, FileStorage."
  }
}

variable "allow_shared_key_access" {
  description = "Whether shared key access is enabled. Defaults to false so applications must use their Entra ID identity and RBAC."
  type        = bool
  default     = false
}

variable "public_network_access_enabled" {
  description = "Whether public network access is enabled. Defaults to true because AKS and App Service applications may not have private endpoints configured."
  type        = bool
  default     = true
}

variable "min_tls_version" {
  description = "Minimum TLS version for the storage account."
  type        = string
  default     = "TLS1_2"

  validation {
    condition     = contains(["TLS1_0", "TLS1_1", "TLS1_2", "TLS1_3"], var.min_tls_version)
    error_message = "min_tls_version must be one of TLS1_0, TLS1_1, TLS1_2, TLS1_3."
  }
}

variable "enable_versioning" {
  description = "Enable blob versioning on the storage account."
  type        = bool
  default     = true
}

variable "enable_change_feed" {
  description = "Enable the blob change feed on the storage account."
  type        = bool
  default     = false
}

variable "delete_retention_days" {
  description = "Number of days to retain deleted blobs."
  type        = number
  default     = 7

  validation {
    condition     = var.delete_retention_days >= 1 && var.delete_retention_days <= 365
    error_message = "delete_retention_days must be between 1 and 365."
  }
}

variable "container_delete_retention_days" {
  description = "Number of days to retain deleted containers."
  type        = number
  default     = 7

  validation {
    condition     = var.container_delete_retention_days >= 1 && var.container_delete_retention_days <= 365
    error_message = "container_delete_retention_days must be between 1 and 365."
  }
}

variable "container_names" {
  description = "Blob container names to create for the application."
  type        = list(string)
  default     = ["uploads", "images", "videos", "reports", "exports"]

  validation {
    condition = alltrue([
      for n in var.container_names :
      length(n) >= 3 &&
      length(n) <= 63 &&
      can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", n))
    ])
    error_message = "container_names must contain only lowercase letters, numbers, and single hyphens, and each name must be 3-63 characters long."
  }
}

variable "role_definition_name" {
  description = "Azure built-in role granted to the application identity on the storage account."
  type        = string
  default     = "Storage Blob Data Contributor"
}

variable "tags" {
  description = "Additional tags to apply to the storage account."
  type        = map(string)
  default     = {}
}
