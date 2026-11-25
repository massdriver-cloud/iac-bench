variable "resource_group_name" {
  description = "Name of the existing Azure resource group where the application's storage account will be created (for example, 'orders-staging' or 'orders-prod')."
  type        = string

  validation {
    condition     = length(trimspace(var.resource_group_name)) > 0 && can(regex("^[a-zA-Z0-9._()-]+$", var.resource_group_name))
    error_message = "resource_group_name must be a valid non-empty Azure resource group name."
  }
}

variable "app_principal_id" {
  description = "Entra ID Object ID (principal_id) of the application's Managed Identity or Service Principal (running on AKS or App Service). Granted data-plane RBAC access to the storage account."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.app_principal_id))
    error_message = "app_principal_id must be a valid UUID / Entra ID Object ID."
  }
}

variable "location" {
  description = "Azure region for the storage account (for example, 'eastus2' or 'westeurope'). Ideally matches the application's resource group location."
  type        = string
  default     = "eastus2"

  validation {
    condition     = length(trimspace(var.location)) > 0
    error_message = "location must not be empty."
  }
}

variable "application_name" {
  description = "Short name of the application (for example, 'orders' or 'billing'). Used for resource naming and standard tags. If omitted, derived from resource_group_name."
  type        = string
  default     = null

  validation {
    condition     = var.application_name == null ? true : can(regex("^[a-zA-Z0-9-]+$", var.application_name))
    error_message = "application_name may only contain alphanumeric characters and hyphens."
  }
}

variable "environment" {
  description = "Deployment environment name (for example, 'dev', 'staging', 'prod'). Used for naming, tagging, and selecting default replication durability (GRS in prod, LRS in non-prod)."
  type        = string
  default     = null

  validation {
    condition     = var.environment == null ? true : can(regex("^[a-zA-Z0-9-]+$", var.environment))
    error_message = "environment may only contain alphanumeric characters and hyphens."
  }
}

variable "storage_account_name" {
  description = "Optional explicit globally-unique Azure Storage Account name (3-24 lowercase letters and numbers). When omitted, a deterministic globally-unique name is automatically generated from the application and resource group."
  type        = string
  default     = null

  validation {
    condition     = var.storage_account_name == null ? true : can(regex("^[a-z0-9]{3,24}$", var.storage_account_name))
    error_message = "storage_account_name must be between 3 and 24 characters long and contain only lowercase letters and numbers."
  }
}

variable "additional_app_principal_ids" {
  description = "Map of additional application or worker Entra ID Object IDs (keyed by logical name, e.g. 'background-worker' = '<uuid>') that need data-plane access to the storage account."
  type        = map(string)
  default     = {}

  validation {
    condition = alltrue([
      for id in values(var.additional_app_principal_ids) :
      can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", id))
    ])
    error_message = "All values in additional_app_principal_ids must be valid UUIDs / Entra ID Object IDs."
  }
}

variable "readonly_principal_ids" {
  description = "Map of Entra ID Object IDs (keyed by logical name) to grant read-only Storage Blob Data Reader access."
  type        = map(string)
  default     = {}

  validation {
    condition = alltrue([
      for id in values(var.readonly_principal_ids) :
      can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", id))
    ])
    error_message = "All values in readonly_principal_ids must be valid UUIDs / Entra ID Object IDs."
  }
}

variable "app_role_definition_name" {
  description = "Azure built-in RBAC role assigned to the application identity for blob data access. Defaults to 'Storage Blob Data Contributor' so the app can read, write, and delete blobs."
  type        = string
  default     = "Storage Blob Data Contributor"

  validation {
    condition = contains([
      "Storage Blob Data Contributor",
      "Storage Blob Data Reader",
      "Storage Blob Data Owner",
      "Storage Blob Delegator"
    ], var.app_role_definition_name)
    error_message = "app_role_definition_name must be one of: 'Storage Blob Data Contributor', 'Storage Blob Data Reader', 'Storage Blob Data Owner', 'Storage Blob Delegator'."
  }
}

variable "enable_user_delegation_sas" {
  description = "Also grant the application identity 'Storage Blob Delegator' role so it can mint short-lived User Delegation SAS URLs for browser uploads/downloads without account keys."
  type        = bool
  default     = true
}

variable "containers" {
  description = "List of blob container names to create for the application (e.g., ['uploads', 'media', 'exports']). All containers are always created with private access."
  type        = list(string)
  default     = ["uploads", "exports"]

  validation {
    condition = alltrue([
      for c in var.containers :
      can(regex("^[a-z0-9](?:[a-z0-9-]{1,61}[a-z0-9])?$", c)) && !can(regex("--", c))
    ])
    error_message = "Each container name must be 3-63 characters, lowercase letters, numbers, and single hyphens, starting and ending with a letter or number."
  }
}

variable "replication_type" {
  description = "Storage replication strategy ('LRS', 'ZRS', 'GRS', 'GZRS', 'RAGRS', 'RAGZRS'). If null, defaults automatically to 'GRS' for production environments and 'LRS' for non-production environments."
  type        = string
  default     = null

  validation {
    condition     = var.replication_type == null ? true : contains(["LRS", "ZRS", "GRS", "GZRS", "RAGRS", "RAGZRS"], var.replication_type)
    error_message = "replication_type must be one of LRS, ZRS, GRS, GZRS, RAGRS, RAGZRS."
  }
}

variable "enable_versioning" {
  description = "Enable blob versioning to protect application files against accidental overwrites."
  type        = bool
  default     = true
}

variable "enable_change_feed" {
  description = "Enable blob change feed for ordered transaction logs of blob modifications."
  type        = bool
  default     = true
}

variable "change_feed_retention_in_days" {
  description = "Number of days to retain blob change feed logs."
  type        = number
  default     = 30

  validation {
    condition     = var.change_feed_retention_in_days >= 1 && var.change_feed_retention_in_days <= 146000
    error_message = "change_feed_retention_in_days must be between 1 and 146000."
  }
}

variable "blob_soft_delete_retention_days" {
  description = "Number of days to retain soft-deleted blobs and versions so accidental deletions can be recovered."
  type        = number
  default     = 14

  validation {
    condition     = var.blob_soft_delete_retention_days >= 1 && var.blob_soft_delete_retention_days <= 365
    error_message = "blob_soft_delete_retention_days must be between 1 and 365."
  }
}

variable "container_soft_delete_retention_days" {
  description = "Number of days to retain soft-deleted containers."
  type        = number
  default     = 14

  validation {
    condition     = var.container_soft_delete_retention_days >= 1 && var.container_soft_delete_retention_days <= 365
    error_message = "container_soft_delete_retention_days must be between 1 and 365."
  }
}

variable "enable_point_in_time_restore" {
  description = "Enable blob point-in-time restore (requires versioning, change feed, and blob soft delete). Retention is automatically set to blob_soft_delete_retention_days - 1."
  type        = bool
  default     = true
}

variable "lifecycle_cool_after_days" {
  description = "Automatically transition blobs to Cool tier after this many days since last access/modification. Set to null to disable."
  type        = number
  default     = 30

  validation {
    condition     = var.lifecycle_cool_after_days == null ? true : (var.lifecycle_cool_after_days >= 1 && var.lifecycle_cool_after_days <= 36500)
    error_message = "lifecycle_cool_after_days must be between 1 and 36500, or null."
  }
}

variable "lifecycle_archive_after_days" {
  description = "Automatically transition blobs to Archive tier after this many days since last modification. Set to null to disable."
  type        = number
  default     = 90

  validation {
    condition     = var.lifecycle_archive_after_days == null ? true : (var.lifecycle_archive_after_days >= 1 && var.lifecycle_archive_after_days <= 36500)
    error_message = "lifecycle_archive_after_days must be between 1 and 36500, or null."
  }
}

variable "lifecycle_delete_previous_versions_after_days" {
  description = "Automatically delete non-current blob versions after this many days to prevent unbounded storage cost growth from versioning."
  type        = number
  default     = 30

  validation {
    condition     = var.lifecycle_delete_previous_versions_after_days >= 1 && var.lifecycle_delete_previous_versions_after_days <= 36500
    error_message = "lifecycle_delete_previous_versions_after_days must be between 1 and 36500."
  }
}

variable "lifecycle_delete_exports_after_days" {
  description = "Optional: automatically delete temporary generated reports/exports in the 'exports' container after this many days. Set to null to keep indefinitely."
  type        = number
  default     = 90

  validation {
    condition     = var.lifecycle_delete_exports_after_days == null ? true : (var.lifecycle_delete_exports_after_days >= 1 && var.lifecycle_delete_exports_after_days <= 36500)
    error_message = "lifecycle_delete_exports_after_days must be between 1 and 36500, or null."
  }
}

variable "cors_allowed_origins" {
  description = "Optional list of allowed origins (for example, ['https://orders.example.com']) for browser direct-to-blob uploads/downloads via User Delegation SAS."
  type        = list(string)
  default     = []
}

variable "cors_allowed_methods" {
  description = "HTTP methods allowed for CORS requests when cors_allowed_origins is non-empty."
  type        = list(string)
  default     = ["GET", "HEAD", "PUT", "POST", "OPTIONS"]
}

variable "network_default_action" {
  description = "Default network firewall action ('Allow' or 'Deny'). When 'Allow' is used without subnet/IP restrictions, public network access remains enabled for App Service and AKS workloads; when 'Deny' is used, only specified virtual_network_subnet_ids, allowed_ip_rules, and trusted Azure services can reach storage."
  type        = string
  default     = "Allow"

  validation {
    condition     = contains(["Allow", "Deny"], var.network_default_action)
    error_message = "network_default_action must be either 'Allow' or 'Deny'."
  }
}

variable "virtual_network_subnet_ids" {
  description = "List of AKS or App Service VNet integration subnet resource IDs allowed through the storage firewall."
  type        = list(string)
  default     = []
}

variable "allowed_ip_rules" {
  description = "List of public IPv4 addresses or CIDR ranges allowed through the storage firewall."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Additional tags to merge with standard application and environment tags on all storage resources."
  type        = map(string)
  default     = {}
}
