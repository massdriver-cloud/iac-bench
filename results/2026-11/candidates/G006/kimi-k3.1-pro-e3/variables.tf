variable "application_name" {
  description = "Short application name used in resource naming and tags, for example 'orders'."
  type        = string

  validation {
    condition = (
      length(trimspace(var.application_name)) > 0 &&
      length(var.application_name) <= 32 &&
      can(regex("[A-Za-z0-9]", var.application_name))
    )
    error_message = "application_name must be 1-32 characters and contain at least one letter or number."
  }
}

variable "environment" {
  description = "Environment name used in resource naming and tags, for example 'staging' or 'prod'."
  type        = string

  validation {
    condition = (
      length(trimspace(var.environment)) > 0 &&
      length(var.environment) <= 16 &&
      can(regex("[A-Za-z0-9]", var.environment))
    )
    error_message = "environment must be 1-16 characters and contain at least one letter or number."
  }
}

variable "resource_group_name" {
  description = "Name of the application's existing resource group. This module does not create or manage the resource group."
  type        = string

  validation {
    condition     = length(trimspace(var.resource_group_name)) > 0
    error_message = "resource_group_name must not be empty."
  }
}

variable "location" {
  description = "Azure region for the storage account, for example 'eastus'. Use the same region as the application."
  type        = string

  validation {
    condition     = length(trimspace(var.location)) > 0
    error_message = "location must not be empty."
  }
}

variable "application_identity_object_id" {
  description = "Object (principal) ID of the application's existing Entra ID identity. For a managed identity this is its principal/object ID, not its client ID."
  type        = string

  validation {
    condition = can(regex(
      "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$",
      var.application_identity_object_id
    ))
    error_message = "application_identity_object_id must be a valid Entra ID object/principal UUID."
  }
}

variable "storage_account_name" {
  description = "Optional globally unique storage account name (3-24 lowercase letters/numbers). Leave null to use the module-generated name."
  type        = string
  default     = null

  validation {
    condition = (
      var.storage_account_name == null ||
      can(regex("^[a-z0-9]{3,24}$", var.storage_account_name))
    )
    error_message = "storage_account_name must be null or 3-24 lowercase letters and numbers."
  }
}

variable "container_names" {
  description = "Private blob containers to create. The application identity can read and write blobs in all of them."
  type        = set(string)
  default     = ["data"]

  validation {
    condition = length(var.container_names) > 0 && alltrue([
      for name in var.container_names : (
        length(name) >= 3 &&
        length(name) <= 63 &&
        can(regex("^[a-z0-9][a-z0-9-]*[a-z0-9]$", name)) &&
        !strcontains(name, "--")
      )
    ])
    error_message = "Provide at least one container name. Names must be 3-63 lowercase letters, numbers, or single hyphens, and start/end with a letter or number."
  }
}

variable "replication_type" {
  description = "Storage redundancy. LRS is the low-cost default; choose ZRS or a geo-redundant option when the application's recovery requirements need it."
  type        = string
  default     = "LRS"

  validation {
    condition = contains(
      ["LRS", "ZRS", "GRS", "RAGRS", "GZRS", "RAGZRS"],
      var.replication_type
    )
    error_message = "replication_type must be one of LRS, ZRS, GRS, RAGRS, GZRS, or RAGZRS."
  }
}

variable "soft_delete_retention_days" {
  description = "Days to retain deleted blobs and containers (7-30). Blob versioning and noncurrent-version cleanup are also enabled."
  type        = number
  default     = 30

  validation {
    condition = (
      var.soft_delete_retention_days >= 7 &&
      var.soft_delete_retention_days <= 30 &&
      floor(var.soft_delete_retention_days) == var.soft_delete_retention_days
    )
    error_message = "soft_delete_retention_days must be a whole number between 7 and 30."
  }
}

variable "noncurrent_version_retention_days" {
  description = "Days to retain noncurrent blob versions and snapshots before lifecycle management removes them. Current blobs are never deleted by this policy."
  type        = number
  default     = 30

  validation {
    condition = (
      var.noncurrent_version_retention_days >= 1 &&
      var.noncurrent_version_retention_days <= 365 &&
      floor(var.noncurrent_version_retention_days) == var.noncurrent_version_retention_days
    )
    error_message = "noncurrent_version_retention_days must be a whole number between 1 and 365."
  }
}

variable "allowed_ip_ranges" {
  description = "Optional public IPv4 addresses/CIDR ranges allowed through the storage firewall. Setting any firewall input changes the default network action to Deny."
  type        = set(string)
  default     = []
}

variable "allowed_subnet_ids" {
  description = "Optional virtual-network subnet IDs with the Microsoft.Storage service endpoint. Setting any firewall input changes the default network action to Deny."
  type        = set(string)
  default     = []
}

variable "public_network_access_enabled" {
  description = "Whether the storage public endpoint is reachable. Disable only when private endpoints are provisioned separately; anonymous blob access remains disabled in all cases."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Additional Azure tags. Application, environment, and managed-by tags are always supplied and can be overridden here."
  type        = map(string)
  default     = {}
}
