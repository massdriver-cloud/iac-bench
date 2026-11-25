variable "application_name" {
  description = "Short application name used in the storage account name and tags."
  type        = string

  validation {
    condition     = length(trimspace(var.application_name)) > 0 && length(var.application_name) <= 64 && can(regex("[A-Za-z0-9]", var.application_name))
    error_message = "application_name must be 1-64 characters and contain at least one letter or digit."
  }
}

variable "resource_group_name" {
  description = "Name of the existing resource group belonging to this application and environment."
  type        = string

  validation {
    condition     = length(trimspace(var.resource_group_name)) > 0
    error_message = "resource_group_name must not be empty."
  }
}

variable "location" {
  description = "Azure region for the storage account (normally the resource group's region)."
  type        = string
}

variable "application_principal_id" {
  description = "Object/principal ID of the application's existing Entra ID service principal or managed identity."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.application_principal_id))
    error_message = "application_principal_id must be a valid Entra ID object ID (UUID)."
  }
}

variable "tags" {
  description = "Optional additional Azure resource tags. application and managed_by are set by the module."
  type        = map(string)
  default     = {}
}
