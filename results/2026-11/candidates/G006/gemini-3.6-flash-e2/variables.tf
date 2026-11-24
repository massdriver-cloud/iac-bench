variable "name" {
  type        = string
  description = "The name of the Azure Storage Account. Must be globally unique, 3-24 characters, lowercase letters and numbers only."

  validation {
    condition     = can(regex("^[a-z0-9]{3,24}$", var.name))
    error_message = "The storage account name must be between 3 and 24 characters in length and use numbers and lower-case letters only."
  }
}

variable "resource_group_name" {
  type        = string
  description = "The name of the existing resource group in which the storage account should be created."
}

variable "location" {
  type        = string
  default     = "eastus"
  description = "The Azure region where the storage account should be created."
}

variable "account_tier" {
  type        = string
  default     = "Standard"
  description = "Defines the Tier to use for this storage account (Standard or Premium)."

  validation {
    condition     = contains(["Standard", "Premium"], var.account_tier)
    error_message = "Account tier must be either 'Standard' or 'Premium'."
  }
}

variable "account_replication_type" {
  type        = string
  default     = "LRS"
  description = "Defines the type of replication to use for this storage account (LRS, GRS, RAGRS, ZRS, GZRS, RAGZRS)."

  validation {
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"], var.account_replication_type)
    error_message = "Account replication type must be one of: LRS, GRS, RAGRS, ZRS, GZRS, RAGZRS."
  }
}

variable "access_tier" {
  type        = string
  default     = "Hot"
  description = "Defines the access tier for BlobStorage, FileStorage and StorageV2 accounts (Hot or Cool)."

  validation {
    condition     = contains(["Hot", "Cool"], var.access_tier)
    error_message = "Access tier must be either 'Hot' or 'Cool'."
  }
}

variable "allow_blob_public_access" {
  type        = bool
  default     = false
  description = "Allow or disallow nested items to be public inside the storage account. Default is false for security."
}

variable "default_to_oauth_authentication" {
  type        = bool
  default     = true
  description = "Default to Azure Active Directory (Entra ID) OAuth authentication in Azure Portal."
}

variable "shared_access_key_enabled" {
  type        = bool
  default     = true
  description = "Indicates whether the storage account permits requests to be authorized with the account access key via Shared Key."
}

variable "public_network_access_enabled" {
  type        = bool
  default     = true
  description = "Whether public network access is allowed for the storage account."
}

variable "min_tls_version" {
  type        = string
  default     = "TLS1_2"
  description = "The minimum supported TLS version for requests to the storage account."

  validation {
    condition     = contains(["TLS1_0", "TLS1_1", "TLS1_2"], var.min_tls_version)
    error_message = "Minimum TLS version must be TLS1_0, TLS1_1, or TLS1_2."
  }
}

variable "blob_versioning_enabled" {
  type        = bool
  default     = true
  description = "Is blob versioning enabled?"
}

variable "blob_change_feed_enabled" {
  type        = bool
  default     = false
  description = "Is blob change feed enabled?"
}

variable "blob_soft_delete_retention_days" {
  type        = number
  default     = 7
  description = "The number of days that deleted blobs should be retained (1 to 365, or 0 to disable)."

  validation {
    condition     = var.blob_soft_delete_retention_days >= 0 && var.blob_soft_delete_retention_days <= 365
    error_message = "Soft delete retention days must be between 0 and 365."
  }
}

variable "container_soft_delete_retention_days" {
  type        = number
  default     = 7
  description = "The number of days that deleted containers should be retained (1 to 365, or 0 to disable)."

  validation {
    condition     = var.container_soft_delete_retention_days >= 0 && var.container_soft_delete_retention_days <= 365
    error_message = "Soft delete retention days must be between 0 and 365."
  }
}

variable "containers" {
  type        = list(string)
  default     = []
  description = "List of blob container names to create in the storage account."
}

variable "principal_ids" {
  type        = list(string)
  default     = []
  description = "List of Entra ID principal IDs (Managed Identities, Service Principals, Users, Groups) to grant storage access to."
}

variable "role_definition_name" {
  type        = string
  default     = "Storage Blob Data Contributor"
  description = "The Azure RBAC role definition name assigned to principal_ids."
}

variable "role_assignments" {
  type = map(object({
    principal_id         = string
    role_definition_name = string
  }))
  default     = {}
  description = "Map of additional custom role assignments to apply at the storage account scope."
}

variable "cors_rules" {
  type = list(object({
    allowed_headers    = list(string)
    allowed_methods    = list(string)
    allowed_origins    = list(string)
    exposed_headers    = list(string)
    max_age_in_seconds = number
  }))
  default     = []
  description = "List of CORS rules to apply to the blob service."
}

variable "network_rules" {
  type = object({
    default_action             = string
    bypass                     = optional(list(string), ["AzureServices"])
    ip_rules                   = optional(list(string), [])
    virtual_network_subnet_ids = optional(list(string), [])
  })
  default     = null
  description = "Network security rules restricting access to the storage account."
}

variable "lifecycle_rules" {
  type = list(object({
    name    = string
    enabled = optional(bool, true)
    filters = optional(object({
      prefix_match = optional(list(string), [])
      blob_types   = optional(list(string), ["blockBlob"])
    }), {})
    actions = object({
      base_blob = optional(object({
        tier_to_cool_after_days_since_modification_greater_than    = optional(number)
        tier_to_archive_after_days_since_modification_greater_than = optional(number)
        delete_after_days_since_modification_greater_than          = optional(number)
      }))
      snapshot = optional(object({
        delete_after_days_since_creation_greater_than = optional(number)
      }))
    })
  }))
  default     = []
  description = "List of lifecycle management rules for automated tiering or deletion."
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "A mapping of tags to assign to the storage account resource."
}
