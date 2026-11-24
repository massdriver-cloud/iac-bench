variable "application_name" {
  description = "Application name used to generate the storage account name and tags."
  type        = string

  validation {
    condition     = length(regexall("[A-Za-z0-9]", var.application_name)) >= 3
    error_message = "application_name must contain at least three letters or digits."
  }
}

variable "resource_group_name" {
  description = "Name of the existing resource group owned by this application."
  type        = string
}

variable "location" {
  description = "Azure region for the storage account (for example, eastus)."
  type        = string
}

variable "application_identity_principal_id" {
  description = "Object/principal ID of the application's existing Entra ID service principal or managed identity."
  type        = string
}

variable "tags" {
  description = "Additional tags to apply to the storage account. Standard application and managed_by tags are always set by this module."
  type        = map(string)
  default     = {}
}
