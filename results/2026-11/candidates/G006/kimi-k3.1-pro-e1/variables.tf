variable "application_name" {
  description = "Short application/workload name, for example 'orders'. It is used in the storage account name and standard tags."
  type        = string

  validation {
    condition = (
      length(trimspace(var.application_name)) > 0 &&
      length(var.application_name) <= 64 &&
      can(regex("[A-Za-z0-9]", var.application_name))
    )
    error_message = "application_name must be 1-64 characters and contain at least one letter or number."
  }
}

variable "resource_group_name" {
  description = "Name of the application's existing resource group, for example 'orders-staging'. The module does not create or manage the resource group."
  type        = string

  validation {
    condition     = length(trimspace(var.resource_group_name)) > 0
    error_message = "resource_group_name must not be empty."
  }
}

variable "location" {
  description = "Azure region for the storage account, for example 'eastus'. Normally this is the same region as the application's resource group."
  type        = string

  validation {
    condition     = length(trimspace(var.location)) > 0
    error_message = "location must not be empty."
  }
}

variable "application_identity_principal_id" {
  description = "Object/principal ID (not client ID) of the application's existing Entra ID managed identity or service principal. It receives Storage Blob Data Contributor on this account."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.application_identity_principal_id))
    error_message = "application_identity_principal_id must be a valid UUID. Use the identity's principal/object ID, not its client ID."
  }
}

variable "container_names" {
  description = "Private blob containers to create for the application. Container names must follow Azure Storage naming rules."
  type        = set(string)
  default     = ["files"]

  validation {
    condition = alltrue([
      for name in var.container_names :
      can(regex("^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$", name)) && !can(regex("--", name))
    ])
    error_message = "Each container name must be 3-63 characters of lowercase letters, numbers, and single hyphens, and must start and end with a letter or number."
  }
}

variable "account_replication_type" {
  description = "Storage redundancy. ZRS is the default for zone-resilient application data; select another supported SKU only when its recovery and cost trade-offs are understood."
  type        = string
  default     = "ZRS"

  validation {
    condition     = contains(["LRS", "ZRS", "GRS", "RAGRS", "GZRS", "RAGZRS"], var.account_replication_type)
    error_message = "account_replication_type must be one of LRS, ZRS, GRS, RAGRS, GZRS, or RAGZRS."
  }
}

variable "storage_account_name" {
  description = "Optional explicit globally unique storage account name. Leave null to use the module's deterministic, subscription-unique naming convention."
  type        = string
  default     = null

  validation {
    condition = (
      var.storage_account_name == null ||
      can(regex("^[a-z0-9]{3,24}$", var.storage_account_name))
    )
    error_message = "storage_account_name must contain only lowercase letters and numbers and be 3-24 characters long."
  }
}

variable "allowed_ip_addresses" {
  description = "Optional public IP addresses or CIDR ranges allowed to reach the storage endpoint. Supplying any IP or subnet rule changes the network default action to Deny."
  type        = set(string)
  default     = []
}

variable "allowed_subnet_ids" {
  description = "Optional virtual-network subnet resource IDs with the Microsoft.Storage service endpoint enabled. Supplying any IP or subnet rule changes the network default action to Deny."
  type        = set(string)
  default     = []
}

variable "tags" {
  description = "Additional Azure tags. The module always enforces its application, component, and managed_by tags."
  type        = map(string)
  default     = {}
}
