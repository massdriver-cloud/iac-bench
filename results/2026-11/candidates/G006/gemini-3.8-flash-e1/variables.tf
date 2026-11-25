variable "application_name" {
  type        = string
  description = "The name of the application (e.g. 'orders'). Used for resource naming and tagging."
}

variable "environment" {
  type        = string
  description = "The target deployment environment (e.g. 'staging', 'prod'). Used for resource naming, replication defaults, and tagging."
}

variable "resource_group_name" {
  type        = string
  description = "The Azure Resource Group name. Defaults to '{application_name}-{environment}' if omitted."
  default     = null
}

variable "location" {
  type        = string
  description = "The Azure region. Defaults to the Resource Group's location if omitted."
  default     = null
}

variable "storage_account_name" {
  type        = string
  description = "Custom storage account name. If omitted, a standard globally unique name conforming to Azure rules (3-24 lowercase alphanumeric characters) is automatically generated."
  default     = null
  validation {
    condition     = var.storage_account_name == null || can(regex("^[a-z0-9]{3,24}$", var.storage_account_name))
    error_message = "Storage account name must be 3-24 characters and contain only lowercase letters and numbers."
  }
}

variable "account_tier" {
  type        = string
  description = "Storage account performance tier ('Standard' or 'Premium'). Defaults to 'Standard'."
  default     = "Standard"
  validation {
    condition     = contains(["Standard", "Premium"], var.account_tier)
    error_message = "account_tier must be either 'Standard' or 'Premium'."
  }
}

variable "account_replication_type" {
  type        = string
  description = "Storage account replication type ('LRS', 'GRS', 'RAGRS', 'ZRS', 'GZRS', 'RAGZRS'). Defaults to 'ZRS' for prod and 'LRS' for non-prod environments."
  default     = null
}

variable "access_tier" {
  type        = string
  description = "The default access tier for blobs ('Hot' or 'Cool'). Defaults to 'Hot'."
  default     = "Hot"
  validation {
    condition     = contains(["Hot", "Cool"], var.access_tier)
    error_message = "access_tier must be either 'Hot' or 'Cool'."
  }
}

variable "containers" {
  type        = list(string)
  description = "List of blob container names to create for application files (e.g. uploads, media, reports)."
  default     = ["uploads", "images", "reports"]
}

variable "custom_containers" {
  type = map(object({
    container_access_type = optional(string, "private")
    metadata              = optional(map(string), {})
  }))
  description = "Optional map of container names to custom container configuration objects for custom settings."
  default     = {}
}

variable "application_principal_id" {
  type        = string
  description = "Microsoft Entra ID object ID of the application's identity (AKS Workload Identity or App Service Managed Identity) to grant Storage Blob Data Contributor access."
  default     = null
}

variable "application_principal_ids" {
  type        = list(string)
  description = "Additional Microsoft Entra ID principal IDs to grant Storage Blob Data Contributor access."
  default     = []
}

variable "role_definition_name" {
  type        = string
  description = "Azure built-in RBAC role granted to application identities. Defaults to 'Storage Blob Data Contributor'."
  default     = "Storage Blob Data Contributor"
}

variable "custom_role_assignments" {
  type = map(object({
    principal_id         = string
    role_definition_name = string
  }))
  description = "Additional custom role assignments to grant on this storage account."
  default     = {}
}

variable "enable_blob_versioning" {
  type        = bool
  description = "Enable blob versioning to protect against accidental overwrites and deletions."
  default     = true
}

variable "blob_soft_delete_retention_days" {
  type        = number
  description = "Number of days that deleted blobs should be retained before permanent removal."
  default     = 7
}

variable "container_soft_delete_retention_days" {
  type        = number
  description = "Number of days that deleted containers should be retained before permanent removal."
  default     = 7
}

variable "enable_lifecycle_management" {
  type        = bool
  description = "Enable automated blob lifecycle management policy."
  default     = false
}

variable "lifecycle_cool_after_days" {
  type        = number
  description = "Days after modification to transition blobs to cool storage (when lifecycle management is enabled)."
  default     = 90
}

variable "lifecycle_delete_after_days" {
  type        = number
  description = "Days after modification to delete blobs (when lifecycle management is enabled). Set to null to disable deletion."
  default     = null
}

variable "network_rules_default_action" {
  type        = string
  description = "Default action when no network rules match ('Allow' or 'Deny'). Defaults to 'Allow'."
  default     = "Allow"
  validation {
    condition     = contains(["Allow", "Deny"], var.network_rules_default_action)
    error_message = "network_rules_default_action must be 'Allow' or 'Deny'."
  }
}

variable "network_bypass" {
  type        = list(string)
  description = "Traffic that should bypass network rules. Defaults to ['AzureServices']."
  default     = ["AzureServices"]
}

variable "allowed_ip_ranges" {
  type        = list(string)
  description = "List of public IP addresses or CIDR blocks allowed to access the storage account."
  default     = []
}

variable "allowed_subnet_ids" {
  type        = list(string)
  description = "List of virtual network subnet IDs allowed to access the storage account."
  default     = []
}

variable "tags" {
  type        = map(string)
  description = "Additional tags to apply to resources. Automatically merged with standard application and environment tags."
  default     = {}
}
