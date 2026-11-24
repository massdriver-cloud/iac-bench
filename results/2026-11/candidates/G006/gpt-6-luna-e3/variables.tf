variable "resource_group_name" {
  description = "Name of the application's existing Azure resource group. The storage account is created in this group and uses its location."
  type        = string
  nullable    = false

  validation {
    condition     = length(trimspace(var.resource_group_name)) > 0
    error_message = "resource_group_name must not be empty."
  }
}

variable "storage_account_name" {
  description = "Globally unique Azure storage account name (3-24 lowercase letters and numbers)."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-z0-9]{3,24}$", var.storage_account_name))
    error_message = "storage_account_name must be 3-24 characters and contain only lowercase letters and numbers."
  }
}

variable "application_principal_id" {
  description = "Object (principal) ID of the application's existing Entra ID identity, used to grant blob data access."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.application_principal_id))
    error_message = "application_principal_id must be a valid Entra ID object ID in UUID format."
  }
}

variable "container_name" {
  description = "Name of the private blob container created for application data."
  type        = string
  default     = "app-data"
  nullable    = false

  validation {
    condition     = can(regex("^[a-z0-9]+(-[a-z0-9]+)*$", var.container_name)) && length(var.container_name) >= 3 && length(var.container_name) <= 63
    error_message = "container_name must be 3-63 characters, lowercase letters or numbers, with single hyphens separating non-empty segments."
  }
}
