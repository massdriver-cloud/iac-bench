variable "application_name" {
  description = "Short name of the application (for example 'orders'). Used to build names and tags."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]*$", var.application_name))
    error_message = "application_name must start with a letter or number and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "environment" {
  description = "Environment the storage belongs to (for example 'staging' or 'prod'). Used to build the resource group name, storage account name, and tags."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]*$", var.environment))
    error_message = "environment must start with a letter or number and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "app_identity_principal_id" {
  description = "Entra ID object ID (principal ID) of the application's managed identity or service principal. The app will receive Storage Blob Data Contributor on the new storage account."
  type        = string

  validation {
    condition = can(regex(
      "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$",
      var.app_identity_principal_id
    ))
    error_message = "app_identity_principal_id must be a GUID (the Entra ID object ID of the app identity)."
  }
}

variable "resource_group_name_override" {
  description = "Set this only if the application resource group does not follow the standard '<application_name>-<environment>' naming pattern. Defaults to '<application_name>-<environment>'."
  type        = string
  default     = null

  validation {
    condition = var.resource_group_name_override == null || can(regex(
      "^[a-zA-Z0-9][a-zA-Z0-9._()-]*$",
      var.resource_group_name_override
    ))
    error_message = "resource_group_name_override must be a valid Azure resource group name."
  }
}

variable "location" {
  description = "Azure region for the storage account. If omitted, the module reads the location from the application resource group."
  type        = string
  default     = null
}

variable "storage_account_name_override" {
  description = "Optional explicit storage account name. If omitted, the module derives a valid name from the application name and environment."
  type        = string
  default     = null

  validation {
    condition = var.storage_account_name_override == null || (
      length(var.storage_account_name_override) >= 3 &&
      length(var.storage_account_name_override) <= 24 &&
      can(regex("^[a-z0-9]+$", var.storage_account_name_override))
    )
    error_message = "storage_account_name_override must be 3-24 lowercase letters or numbers."
  }
}

variable "containers" {
  description = "Blob containers to create. Defaults to the containers most app teams need for files."
  type        = list(string)
  default     = ["uploads", "images", "videos", "reports", "exports"]

  validation {
    condition = alltrue([
      for c in var.containers :
      can(regex("^[a-z0-9][a-z0-9-]*$", c)) && length(c) >= 3 && length(c) <= 63
    ])
    error_message = "Container names must be 3-63 lowercase letters, numbers, or hyphens, and must start with a letter or number."
  }
}

variable "account_replication_type" {
  description = "Storage account replication type. LRS is the standard, cost-effective default; override only when the app has a specific durability or zone-redundancy requirement."
  type        = string
  default     = "LRS"

  validation {
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"], var.account_replication_type)
    error_message = "account_replication_type must be one of LRS, GRS, RAGRS, ZRS, GZRS, RAGZRS."
  }
}

variable "access_tier" {
  description = "Blob access tier for the storage account."
  type        = string
  default     = "Hot"

  validation {
    condition     = contains(["Hot", "Cool"], var.access_tier)
    error_message = "access_tier must be either 'Hot' or 'Cool'."
  }
}

variable "allow_blob_public_access" {
  description = "Allow anonymous/public access to blobs. Defaults to false so containers and blobs are private by default."
  type        = bool
  default     = false
}

variable "public_network_access_enabled" {
  description = "Whether the storage account can be reached over the public Azure endpoint. Defaults to true so AKS and App Service apps can reach it without private networking."
  type        = bool
  default     = true
}

variable "shared_access_key_enabled" {
  description = "Whether shared access key authentication is enabled. Defaults to false so the application identity is used instead of storage account keys."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Additional tags to apply to all resources. Standard application/environment tags are always added."
  type        = map(string)
  default     = {}
}