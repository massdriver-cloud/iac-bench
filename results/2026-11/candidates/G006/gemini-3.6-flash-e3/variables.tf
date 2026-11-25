variable "storage_account_name" {
  type        = string
  description = "The name of the Azure Storage Account. Must be globally unique, 3-24 characters, lowercase alphanumeric only."

  validation {
    condition     = can(regex("^[a-z0-9]{3,24}$", var.storage_account_name))
    error_message = "Storage account name must be 3-24 characters long and contain only lowercase letters and numbers."
  }
}

variable "name" {
  type        = string
  default     = null
  description = "Optional alias for storage_account_name."
}

variable "resource_group_name" {
  type        = string
  description = "The name of the resource group in which to create the storage account."
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
  description = "Defines the type of replication to use for this storage account (LRS, ZRS, GRS, RAGRS, GZRS, RAGZRS)."

  validation {
    condition     = contains(["LRS", "ZRS", "GRS", "RAGRS", "GZRS", "RAGZRS"], var.account_replication_type)
    error_message = "Replication type must be one of: LRS, ZRS, GRS, RAGRS, GZRS, RAGZRS."
  }
}

variable "account_kind" {
  type        = string
  default     = "StorageV2"
  description = "Defines the Kind of account (BlobStorage, BlockBlobStorage, FileStorage, Storage, StorageV2)."
}

variable "min_tls_version" {
  type        = string
  default     = "TLS1_2"
  description = "The minimum supported TLS version for requests to the storage account."
}

variable "allow_nested_items_to_be_public" {
  type        = bool
  default     = false
  description = "Allow or disallow nested items (blobs/containers) to be publicly accessible. Defaults to false for security."
}

variable "shared_access_key_enabled" {
  type        = bool
  default     = true
  description = "Indicates whether the storage account permits requests to be authorized with the account access key via Shared Key."
}

variable "default_to_oauth_authentication" {
  type        = bool
  default     = true
  description = "Default to Entra ID (OAuth) authentication when browsing storage in Azure portal."
}

variable "public_network_access_enabled" {
  type        = bool
  default     = true
  description = "Whether public network access is allowed for the storage account."
}

variable "containers" {
  type        = list(string)
  default     = []
  description = "List of blob container names to create within the storage account."
}

variable "queues" {
  type        = list(string)
  default     = []
  description = "List of storage queues to create within the storage account."
}

variable "tables" {
  type        = list(string)
  default     = []
  description = "List of storage tables to create within the storage account."
}

variable "file_shares" {
  type = list(object({
    name  = string
    quota = optional(number, 50)
  }))
  default     = []
  description = "List of file shares to create within the storage account."
}

variable "enable_versioning" {
  type        = bool
  default     = true
  description = "Enable blob versioning for automatic data protection."
}

variable "blob_soft_delete_retention_days" {
  type        = number
  default     = 7
  description = "Number of days to retain deleted blobs. Set to 0 to disable blob soft delete."
}

variable "container_soft_delete_retention_days" {
  type        = number
  default     = 7
  description = "Number of days to retain deleted blob containers. Set to 0 to disable container soft delete."
}

variable "principal_ids" {
  type        = list(string)
  default     = []
  description = "List of Entra ID principal IDs (e.g. AKS Workload Identity or App Service Managed Identity) to grant Storage Blob Data Contributor access."
}

variable "app_principal_ids" {
  type        = list(string)
  default     = []
  description = "Alias for principal_ids. List of Entra ID principal IDs to grant Storage Blob Data Contributor access."
}

variable "role_assignments" {
  type = map(object({
    principal_id         = string
    role_definition_name = string
  }))
  default     = {}
  description = "Map of custom RBAC role assignments to apply at the storage account level."
}

variable "allowed_ips" {
  type        = list(string)
  default     = []
  description = "List of IP addresses or IP ranges in CIDR format allowed to access the storage account."
}

variable "allowed_subnet_ids" {
  type        = list(string)
  default     = []
  description = "List of Virtual Network Subnet IDs allowed to access the storage account."
}

variable "network_default_action" {
  type        = string
  default     = "Allow"
  description = "Specifies the default action of allow or deny when no other rules match. Valid values are Allow or Deny."

  validation {
    condition     = contains(["Allow", "Deny"], var.network_default_action)
    error_message = "network_default_action must be either 'Allow' or 'Deny'."
  }
}

variable "network_bypass" {
  type        = list(string)
  default     = ["Logging", "Metrics", "AzureServices"]
  description = "Specifies whether traffic is bypassed for Logging/Metrics/AzureServices."
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "A mapping of tags to assign to the resources."
}
