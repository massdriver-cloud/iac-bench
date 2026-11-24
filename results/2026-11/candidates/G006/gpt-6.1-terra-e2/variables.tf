variable "resource_group_name" {
  description = "Name of the application's existing resource group."
  type        = string

  validation {
    condition     = length(trimspace(var.resource_group_name)) > 0
    error_message = "Provide an existing resource group name."
  }
}

variable "location" {
  description = "Azure region of the existing application resource group, for example eastus."
  type        = string

  validation {
    condition     = length(trimspace(var.location)) > 0
    error_message = "Provide an Azure location."
  }
}

variable "storage_account_name" {
  description = "Globally unique Azure storage account name, 3–24 lowercase letters and digits."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{3,24}$", var.storage_account_name))
    error_message = "Storage account name must contain 3–24 lowercase letters and digits."
  }
}

variable "application_principal_id" {
  description = "Entra object (principal) ID of the application's service principal or managed identity, not its client ID."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.application_principal_id))
    error_message = "application_principal_id must be an Entra object ID in UUID format."
  }
}

variable "replication_type" {
  description = "Storage redundancy: LRS by default; choose ZRS, GRS, or GZRS where supported for stronger resilience."
  type        = string
  default     = "LRS"

  validation {
    condition     = contains(["LRS", "ZRS", "GRS", "GZRS"], var.replication_type)
    error_message = "replication_type must be LRS, ZRS, GRS, or GZRS."
  }
}

variable "tags" {
  description = "Tags to apply to the storage account."
  type        = map(string)
  default     = {}
}
