variable "application" {
  description = "Short application name, e.g. \"orders\". Storage is placed in the existing resource group \"<application>-<environment>\"."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,30}[a-z0-9]$", var.application))
    error_message = "application must be 3-32 chars of lowercase letters, digits and hyphens, starting with a letter."
  }
}

variable "environment" {
  description = "Environment name: dev, test, staging or prod."
  type        = string

  validation {
    condition     = contains(["dev", "test", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, test, staging, prod."
  }
}

variable "location" {
  description = "Azure region of the application's resource group, e.g. \"westeurope\"."
  type        = string
}

variable "app_principal_id" {
  description = "Object (principal) ID of the application's Entra ID identity (managed identity or service principal). It is granted read/write access to the blobs."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.app_principal_id))
    error_message = "app_principal_id must be a GUID (the identity's object ID, not its client ID)."
  }
}

variable "containers" {
  description = "Names of the private blob containers to create (e.g. [\"uploads\", \"reports\"])."
  type        = list(string)
  default     = ["files"]

  validation {
    condition     = length(var.containers) > 0 && alltrue([for c in var.containers : can(regex("^[a-z0-9](?:[a-z0-9]|-[a-z0-9]){2,62}$", c))])
    error_message = "Container names must be 3-63 chars of lowercase letters, digits and single hyphens, starting and ending with a letter or digit."
  }
}

variable "tags" {
  description = "Extra tags to apply to the storage account."
  type        = map(string)
  default     = {}
}
