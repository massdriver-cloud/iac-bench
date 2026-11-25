variable "resource_group_name" {
  description = "Name of the application's existing resource group in this environment. Storage inherits its location."
  type        = string
  nullable    = false
  validation {
    condition     = length(trimspace(var.resource_group_name)) > 0
    error_message = "resource_group_name must not be empty."
  }
}

variable "storage_account_name" {
  description = "Globally unique storage account name: 3-24 lowercase letters and digits (for example, ordersprodfiles123)."
  type        = string
  nullable    = false
  validation {
    condition     = can(regex("^[a-z0-9]{3,24}$", var.storage_account_name))
    error_message = "Use 3-24 lowercase letters and digits for the storage account name."
  }
}

variable "application_principal_id" {
  description = "Entra object/principal ID of the application's existing managed identity or service principal, NOT its client/application ID."
  type        = string
  nullable    = false
  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.application_principal_id))
    error_message = "application_principal_id must be an Entra object ID in UUID format."
  }
}

variable "containers" {
  description = "Private blob containers to create. Use separate containers for logical file groups; files is sufficient for most apps."
  type        = set(string)
  default     = ["files"]
  nullable    = false
  validation {
    condition = length(var.containers) > 0 && alltrue([
      for name in var.containers : can(regex("^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$", name)) && !strcontains(name, "--")
    ])
    error_message = "Provide at least one container; names must be 3-63 lowercase letters, digits or single hyphens, starting and ending with a letter or digit."
  }
}

variable "tags" {
  description = "Additional account tags. Resource group tags are inherited, with these values taking precedence."
  type        = map(string)
  default     = {}
  nullable    = false
}
