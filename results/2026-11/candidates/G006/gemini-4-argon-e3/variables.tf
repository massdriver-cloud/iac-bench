variable "app_name" {
  description = "Short name of the application owning this storage account (for example, 'orders'). Used for naming, tagging, and default resource group resolution."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,30}[a-z0-9]$", var.app_name))
    error_message = "app_name must be 3-32 characters of lowercase letters, numbers, and hyphens, and cannot start or end with a hyphen."
  }
}

variable "environment" {
  description = "Deployment environment name (for example, 'dev', 'staging', 'prod'). Controls data protection and redundancy defaults."
  type        = string

  validation {
    condition     = contains(["dev", "test", "qa", "staging", "uat", "prod", "production"], var.environment)
    error_message = "environment must be one of: dev, test, qa, staging, uat, prod, production."
  }
}

variable "location" {
  description = "Azure region where the storage account will be created (typically matching the application's resource group, such as 'eastus2')."
  type        = string

  validation {
    condition     = length(trimspace(var.location)) > 0
    error_message = "location must not be empty."
  }
}

variable "app_principal_id" {
  description = "Entra ID object (principal) ID of the application's identity (Managed Identity or Service Principal used on AKS / App Service). Granted Storage Blob Data Contributor on the storage account."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.app_principal_id))
    error_message = "app_principal_id must be a valid UUID (Entra ID principal/object ID)."
  }
}

variable "resource_group_name" {
  description = "Name of the existing application resource group. Defaults to '<app_name>-<environment>' (for example, 'orders-staging')."
  type        = string
  default     = null

  validation {
    condition     = var.resource_group_name == null || can(regex("^[a-zA-Z0-9._()-]{1,90}$", var.resource_group_name))
    error_message = "resource_group_name must be a valid Azure resource group name (1-90 characters)."
  }
}

variable "storage_account_name" {
  description = "Optional explicit storage account name override. When omitted, a globally unique name is generated automatically from app_name and environment."
  type        = string
  default     = null

  validation {
    condition     = var.storage_account_name == null || can(regex("^[a-z0-9]{3,24}$", var.storage_account_name))
    error_message = "storage_account_name must be 3-24 characters of lowercase letters and numbers only."
  }
}

variable "containers" {
  description = "Map of blob containers to create in the storage account. Key is the container name; value configures optional metadata and lifecycle policy for blobs in that container."
  type = map(object({
    metadata                   = optional(map(string), {})
    cool_tier_after_days       = optional(number)
    cold_tier_after_days       = optional(number)
    archive_tier_after_days    = optional(number)
    delete_after_days          = optional(number)
    delete_versions_after_days = optional(number, 90)
  }))
  default = {
    uploads = {}
    exports = {
      cool_tier_after_days = 30
      delete_after_days    = 90
    }
  }

  validation {
    condition = alltrue([
      for name, _ in var.containers : can(regex("^[a-z0-9]([a-z0-9-]{1,61}[a-z0-9])?$", name)) && !can(regex("--", name))
    ])
    error_message = "All container names must be 3-63 characters of lowercase letters, numbers, and single hyphens."
  }
}

variable "replication_type" {
  description = "Storage replication strategy override (LRS, ZRS, GRS, GZRS, RAGRS, RAGZRS). Defaults to ZRS in prod/production and LRS in non-production environments."
  type        = string
  default     = null

  validation {
    condition     = var.replication_type == null || contains(["LRS", "ZRS", "GRS", "GZRS", "RAGRS", "RAGZRS"], var.replication_type)
    error_message = "replication_type must be one of: LRS, ZRS, GRS, GZRS, RAGRS, RAGZRS."
  }
}

variable "soft_delete_retention_days" {
  description = "Number of days to retain soft-deleted blobs and containers (1-365). Defaults to 30 days in prod/production and 7 days in non-production environments."
  type        = number
  default     = null

  validation {
    condition     = var.soft_delete_retention_days == null || (var.soft_delete_retention_days >= 1 && var.soft_delete_retention_days <= 365)
    error_message = "soft_delete_retention_days must be between 1 and 365."
  }
}

variable "versioning_enabled" {
  description = "Whether blob versioning is enabled to protect application files against accidental overwrite."
  type        = bool
  default     = true
}

variable "shared_access_key_enabled" {
  description = "Whether storage account shared keys (connection strings / SAS keys signed with account keys) are enabled. Disabled by default in favor of Entra ID identity authentication."
  type        = bool
  default     = false
}

variable "additional_contributor_principal_ids" {
  description = "Additional Entra ID principal IDs to grant Storage Blob Data Contributor access (for example, background workers or companion services)."
  type        = set(string)
  default     = []
}

variable "additional_reader_principal_ids" {
  description = "Additional Entra ID principal IDs to grant read-only Storage Blob Data Reader access (for example, reporting services or support groups)."
  type        = set(string)
  default     = []
}

variable "cors_rules" {
  description = "Optional CORS rules for browser-direct uploads or asset downloads."
  type = list(object({
    allowed_origins    = list(string)
    allowed_methods    = optional(list(string), ["GET", "HEAD", "PUT", "POST"])
    allowed_headers    = optional(list(string), ["*"])
    exposed_headers    = optional(list(string), ["*"])
    max_age_in_seconds = optional(number, 3600)
  }))
  default = []
}

variable "network_rules" {
  description = "Optional network access restrictions for the storage account when restricting traffic to specific AKS/App Service VNet subnets or IP ranges."
  type = object({
    default_action             = optional(string, "Deny")
    bypass                     = optional(set(string), ["AzureServices"])
    ip_rules                   = optional(set(string), [])
    virtual_network_subnet_ids = optional(set(string), [])
  })
  default = null
}

variable "tags" {
  description = "Additional tags to merge with standard application and environment tags."
  type        = map(string)
  default     = {}
}
