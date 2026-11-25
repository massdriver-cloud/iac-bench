variable "application" {
  description = "Short name of the application that owns this storage, e.g. \"orders\". Lowercase letters, digits and hyphens."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,30}[a-z0-9]$", var.application))
    error_message = "application must be 3-32 characters of lowercase letters, digits and hyphens, starting with a letter."
  }
}

variable "environment" {
  description = "Environment name, e.g. \"dev\", \"staging\" or \"prod\". Together with application this selects the resource group \"<application>-<environment>\"."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,15}$", var.environment))
    error_message = "environment must be 2-16 lowercase letters/digits, starting with a letter (e.g. dev, staging, prod)."
  }
}

variable "location" {
  description = "Azure region for the storage account. Use the same region as the application's resource group, e.g. \"westeurope\"."
  type        = string
}

variable "application_principal_id" {
  description = "Object (principal) ID of the application's Entra ID identity (managed identity / workload identity service principal). It is granted read/write access to the blob data."
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
  description = "Override for the resource group name. Leave null to use the standard \"<application>-<environment>\"."
  type        = string
  default     = null
}

variable "tags" {
  description = "Extra tags to apply to the storage account."
  type        = map(string)
  default     = {}
}
