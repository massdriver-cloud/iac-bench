variable "app_name" {
  type        = string
  description = "Short name of the application. Used to build the resource names and tags."

  validation {
    condition     = length(var.app_name) >= 3 && can(regex("^[a-zA-Z0-9][a-zA-Z0-9-]*$", var.app_name))
    error_message = "app_name must be at least 3 characters and contain only letters, numbers, and hyphens (and must not start with a hyphen)."
  }
}

variable "environment" {
  type        = string
  default     = "dev"
  description = "Environment name (for example: dev, staging, prod). Used in naming and tags, and to pick a sensible replication default."

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-]*$", var.environment))
    error_message = "environment must contain only letters, numbers, and hyphens (and must not start with a hyphen)."
  }
}

variable "resource_group_name" {
  type        = string
  description = "Name of the application's existing resource group. The storage account is created in this group."

  validation {
    condition     = length(var.resource_group_name) > 0
    error_message = "resource_group_name must not be empty."
  }
}

variable "location" {
  type        = string
  default     = null
  description = "Azure region for the storage account. When omitted, the resource group's location is used automatically."
}

variable "storage_account_name" {
  type        = string
  default     = null
  description = "Optional explicit globally unique storage account name. When omitted, a unique name is generated from app_name and environment."

  validation {
    condition = var.storage_account_name == null || (
      length(var.storage_account_name) >= 3 &&
      length(var.storage_account_name) <= 24 &&
      can(regex("^[a-z0-9]+$", var.storage_account_name))
    )
    error_message = "storage_account_name, when set, must be 3-24 lowercase letters or numbers."
  }
}

variable "account_tier" {
  type        = string
  default     = "Standard"
  description = "Storage account performance tier. Standard is correct for virtually all application data."

  validation {
    condition     = contains(["Standard", "Premium"], var.account_tier)
    error_message = "account_tier must be Standard or Premium."
  }
}

variable "account_kind" {
  type        = string
  default     = "StorageV2"
  description = "Storage account kind. StorageV2 is the general-purpose default."

  validation {
    condition     = contains(["StorageV2", "Storage", "BlobStorage", "FileStorage", "BlockBlobStorage"], var.account_kind)
    error_message = "account_kind must be one of StorageV2, Storage, BlobStorage, FileStorage, BlockBlobStorage."
  }
}

variable "account_replication_type" {
  type        = string
  default     = null
  description = "Replication type. Defaults to GRS for prod environments and LRS for everything else."

  validation {
    condition = var.account_replication_type == null || contains(
      ["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"],
      var.account_replication_type
    )
    error_message = "account_replication_type must be one of LRS, GRS, RAGRS, ZRS, GZRS, RAGZRS."
  }
}

variable "min_tls_version" {
  type        = string
  default     = "TLS1_2"
  description = "Minimum TLS version accepted by the storage account."

  validation {
    condition     = contains(["TLS1_0", "TLS1_1", "TLS1_2", "TLS1_3"], var.min_tls_version)
    error_message = "min_tls_version must be TLS1_0, TLS1_1, TLS1_2, or TLS1_3."
  }
}

variable "shared_access_key_enabled" {
  type        = bool
  default     = false
  description = "Whether shared access keys are enabled. Disabled by default so applications authenticate with their Entra ID identity."
}

variable "allow_nested_items_to_be_public" {
  type        = bool
  default     = false
  description = "Whether blobs or containers may ever be made publicly accessible. Defaults to false."
}

variable "public_network_access_enabled" {
  type        = bool
  default     = true
  description = "Whether the storage account is reachable from public networks. Set false only when using private endpoints."
}

variable "containers" {
  type        = list(string)
  default     = []
  description = "Names of private blob containers to create (for example uploads, images, videos, reports, exports)."

  validation {
    condition = alltrue([
      for c in var.containers :
      can(regex("^[a-z0-9][a-z0-9-]{2,62}$", c))
    ])
    error_message = "Container names must be 3-63 lowercase letters, numbers, or hyphens."
  }
}

variable "principal_id" {
  type        = string
  default     = null
  description = "Object ID of the application's Entra ID identity (managed identity or service principal) to grant blob data access to."
}

variable "role_definition_name" {
  type        = string
  default     = "Storage Blob Data Contributor"
  description = "Azure RBAC role granted to principal_id on the storage account."
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Additional tags merged with the module's default tags."
}
