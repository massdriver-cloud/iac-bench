variable "application_name" {
  description = "Short name of the application, e.g. \"orders\". Must match the prefix of the application's resource group (\"<application_name>-<environment>\")."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,30}[a-z0-9]$", var.application_name))
    error_message = "application_name must be 3-32 characters of lowercase letters, digits and hyphens, starting with a letter."
  }
}

variable "environment" {
  description = "Environment the storage is for. One of: dev, test, staging, prod."
  type        = string

  validation {
    condition     = contains(["dev", "test", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, test, staging, prod."
  }
}

variable "location" {
  description = "Azure region to create the storage account in; use the same region as the application's resource group, e.g. \"westeurope\"."
  type        = string
}

variable "application_principal_id" {
  description = "Object (principal) ID of the application's existing Entra ID identity (managed identity or service principal). It is granted read/write access to the blob data."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.application_principal_id))
    error_message = "application_principal_id must be a GUID (the identity's object ID, not its client ID)."
  }
}

variable "containers" {
  description = "Names of the private blob containers to create, e.g. [\"uploads\", \"reports\"]."
  type        = list(string)
  default     = ["files"]

  validation {
    condition     = length(var.containers) > 0 && alltrue([for c in var.containers : can(regex("^[a-z0-9](?:[a-z0-9]|-[a-z0-9]){2,62}$", c))])
    error_message = "Each container name must be 3-63 characters of lowercase letters, digits and single hyphens, starting and ending with a letter or digit."
  }
}

variable "resource_group_name" {
  description = "Override for the target resource group. Leave null to use the standard \"<application_name>-<environment>\" group."
  type        = string
  default     = null
}

variable "tags" {
  description = "Additional tags to apply to the storage account."
  type        = map(string)
  default     = {}
}
