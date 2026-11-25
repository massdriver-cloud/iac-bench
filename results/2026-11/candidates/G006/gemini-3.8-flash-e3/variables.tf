variable "application_name" {
  description = "The name of the application (e.g. 'orders'). Used to generate the storage account name and resource tags."
  type        = string
}

variable "environment" {
  description = "The deployment environment (e.g. 'staging', 'prod'). Determines replication type (ZRS in prod, LRS in non-prod) and naming."
  type        = string
}

variable "resource_group_name" {
  description = "The name of the application's existing resource group where storage belongs (e.g. 'orders-staging')."
  type        = string
}

variable "location" {
  description = "The Azure region for the storage account. Defaults to the standard region 'eastus'."
  type        = string
  default     = "eastus"
}

variable "storage_account_name" {
  description = "Optional explicit name for the Azure Storage Account. If omitted, the module automatically generates a compliant, unique name."
  type        = string
  default     = null

  validation {
    condition     = var.storage_account_name == null || can(regex("^[a-z0-9]{3,24}$", var.storage_account_name))
    error_message = "Storage account name must be between 3 and 24 characters and contain only lowercase letters and numbers."
  }
}

variable "app_name" {
  description = "Optional alias for application_name."
  type        = string
  default     = null
}

variable "replication_type" {
  description = "Storage replication type (e.g. 'LRS', 'ZRS', 'GRS'). If null, defaults to 'ZRS' for production and 'LRS' for other environments."
  type        = string
  default     = null

  validation {
    condition     = var.replication_type == null || contains(["LRS", "ZRS", "GRS", "GZRS", "RAGRS", "RAGZRS"], coalesce(var.replication_type, "LRS"))
    error_message = "Replication type must be one of LRS, ZRS, GRS, GZRS, RAGRS, or RAGZRS."
  }
}

variable "account_tier" {
  description = "The performance tier for the storage account. Defaults to 'Standard'."
  type        = string
  default     = "Standard"
}

variable "access_tier" {
  description = "The default access tier for BlobStorage. Defaults to 'Hot'."
  type        = string
  default     = "Hot"
}

variable "containers" {
  description = "List of blob container names to create for the application. Defaults to standard containers for user uploads, media, and reports."
  type        = list(string)
  default     = ["uploads", "media", "reports"]
}

variable "container_access_type" {
  description = "The access level configured for blob containers. Defaults to 'private' to block public anonymous access."
  type        = string
  default     = "private"
}

variable "principal_id" {
  description = "Entra ID Object ID of the application's identity (AKS Workload Identity or App Service Managed Identity) to grant Storage Blob Data Contributor."
  type        = string
  default     = null
}

variable "app_principal_id" {
  description = "Alias for principal_id."
  type        = string
  default     = null
}

variable "principal_ids" {
  description = "List of Entra ID Object IDs to grant Storage Blob Data Contributor access on the storage account."
  type        = list(string)
  default     = []
}

variable "reader_principal_ids" {
  description = "List of Entra ID Object IDs to grant Storage Blob Data Reader access on the storage account."
  type        = list(string)
  default     = []
}

variable "role_definition_name" {
  description = "The RBAC role to assign to the application principal. Defaults to 'Storage Blob Data Contributor'."
  type        = string
  default     = "Storage Blob Data Contributor"
}

variable "shared_access_key_enabled" {
  description = "Whether shared key access is permitted. Defaults to false in alignment with Entra ID-only security best practices."
  type        = bool
  default     = false
}

variable "allow_nested_items_to_be_public" {
  description = "Allow or disallow anonymous public blob access on the storage account. Defaults to false."
  type        = bool
  default     = false
}

variable "public_network_access_enabled" {
  description = "Whether public network access is enabled for the storage account. Defaults to true to allow AKS and App Service connectivity."
  type        = bool
  default     = true
}

variable "infrastructure_encryption_enabled" {
  description = "Enables double encryption at rest for Azure Storage service and infrastructure. Defaults to true."
  type        = bool
  default     = true
}

variable "blob_versioning_enabled" {
  description = "Enables blob versioning for data protection and recovery. Defaults to true."
  type        = bool
  default     = true
}

variable "blob_delete_retention_days" {
  description = "Number of days that deleted blobs should be retained for soft delete recovery. Defaults to 7."
  type        = number
  default     = 7
}

variable "container_delete_retention_days" {
  description = "Number of days that deleted containers should be retained for soft delete recovery. Defaults to 7."
  type        = number
  default     = 7
}

variable "network_rules" {
  description = "Optional network firewall rules for the storage account."
  type = object({
    default_action             = string
    bypass                     = optional(list(string), ["AzureServices", "Logging", "Metrics"])
    ip_rules                   = optional(list(string), [])
    virtual_network_subnet_ids = optional(list(string), [])
  })
  default = null
}

variable "tags" {
  description = "Additional tags to merge with the standard module tags."
  type        = map(string)
  default     = {}
}
