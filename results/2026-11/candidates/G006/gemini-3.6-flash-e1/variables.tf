variable "resource_group_name" {
  type        = string
  description = "The name of the existing resource group where storage account will be created."
}

variable "application_name" {
  type        = string
  description = "The name of the application using this storage account."
}

variable "location" {
  type        = string
  default     = "eastus"
  description = "The Azure location/region where the storage account should be created."
}

variable "environment" {
  type        = string
  default     = "prod"
  description = "Environment name (e.g. dev, staging, prod)."
}

variable "storage_account_name" {
  type        = string
  default     = null
  description = "Optional explicit storage account name. If omitted, a name is generated based on application_name, environment, and resource_group_name."
}

variable "account_tier" {
  type        = string
  default     = "Standard"
  description = "Defines the Tier to use for this storage account (Standard or Premium)."
}

variable "replication_type" {
  type        = string
  default     = "LRS"
  description = "Defines the type of replication to use for this storage account (LRS, GRS, RAGRS, ZRS, GZRS, RAGZRS)."
}

variable "account_kind" {
  type        = string
  default     = "StorageV2"
  description = "Defines the Kind of account (BlobStorage, BlockBlobStorage, FileStorage, Storage, StorageV2)."
}

variable "allow_nested_items_to_be_public" {
  type        = bool
  default     = false
  description = "Allow or disallow nested items within this account to be publicly accessible."
}

variable "shared_access_key_enabled" {
  type        = bool
  default     = true
  description = "Indicates whether the storage account permits requests to be authorized with the account access key via Shared Key."
}

variable "default_to_oauth_authentication" {
  type        = bool
  default     = true
  description = "Default to Azure AD (OAuth) authentication when accessing data in the Azure portal."
}

variable "public_network_access_enabled" {
  type        = bool
  default     = true
  description = "Whether public network access is enabled for the storage account."
}

variable "cross_tenant_replication_enabled" {
  type        = bool
  default     = false
  description = "Should cross Tenant replication be enabled?"
}

variable "enable_blob_properties" {
  type        = bool
  default     = true
  description = "Enable blob properties configuration including soft delete and versioning."
}

variable "enable_versioning" {
  type        = bool
  default     = false
  description = "Enable blob versioning."
}

variable "blob_soft_delete_retention_days" {
  type        = number
  default     = 7
  description = "Retention period in days for deleted blobs. Set to 0 to disable."
}

variable "container_soft_delete_retention_days" {
  type        = number
  default     = 7
  description = "Retention period in days for deleted containers. Set to 0 to disable."
}

variable "containers" {
  type        = list(string)
  default     = []
  description = "List of blob container names to create."
}

variable "file_shares" {
  type        = map(number)
  default     = {}
  description = "Map of file share names to their quota in GB."
}

variable "queues" {
  type        = list(string)
  default     = []
  description = "List of storage queue names to create."
}

variable "tables" {
  type        = list(string)
  default     = []
  description = "List of storage table names to create."
}

variable "app_principal_id" {
  type        = string
  default     = null
  description = "Optional single Entra ID principal ID (Managed Identity / Service Principal) to grant storage access to."
}

variable "app_principal_ids" {
  type        = list(string)
  default     = []
  description = "List of Entra ID principal IDs (Managed Identities / Service Principals) to grant storage access to."
}

variable "role_names" {
  type        = list(string)
  default     = ["Storage Blob Data Contributor"]
  description = "List of RBAC role definition names to assign to the app_principal_ids."
}

variable "network_rules" {
  type = object({
    default_action             = string
    bypass                     = optional(list(string), ["AzureServices"])
    ip_rules                   = optional(list(string), [])
    virtual_network_subnet_ids = optional(list(string), [])
  })
  default     = null
  description = "Network rules object for restricting access to specific networks or IP ranges."
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "A mapping of tags to assign to the resource."
}
