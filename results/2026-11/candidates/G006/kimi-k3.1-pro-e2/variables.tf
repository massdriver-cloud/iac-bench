variable "application_name" {
  description = "A short application name, for example 'orders'. It is used in the storage account name and tags."
  type        = string

  validation {
    condition     = length(var.application_name) <= 64 && can(regex("[A-Za-z0-9]", var.application_name))
    error_message = "application_name must contain at least one letter or number and be no more than 64 characters."
  }
}

variable "resource_group_name" {
  description = "Name of the application's existing resource group, for example 'orders-staging'."
  type        = string

  validation {
    condition     = length(trimspace(var.resource_group_name)) > 0
    error_message = "resource_group_name must not be empty."
  }
}

variable "application_principal_id" {
  description = "Object (principal) ID of the application's existing Entra ID workload identity or managed identity."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.application_principal_id))
    error_message = "application_principal_id must be the identity's object ID in UUID format, not its client ID."
  }
}

variable "containers" {
  description = "Private blob containers to create. Container names must follow Azure's lowercase DNS naming rules."
  type        = set(string)
  default     = ["uploads"]

  validation {
    condition = alltrue([
      for name in var.containers :
      length(name) >= 3 &&
      length(name) <= 63 &&
      can(regex("^[a-z0-9][a-z0-9-]*[a-z0-9]$", name)) &&
      !can(regex("--", name))
    ])
    error_message = "Each container name must be 3-63 characters of lowercase letters, numbers, and single hyphens, and must start and end with a letter or number."
  }
}

variable "replication_type" {
  description = "Azure Storage redundancy. LRS is the portable, cost-conscious default; choose ZRS or a geo-redundant option when required."
  type        = string
  default     = "LRS"

  validation {
    condition     = contains(["LRS", "ZRS", "GRS", "RAGRS", "GZRS", "RAGZRS"], var.replication_type)
    error_message = "replication_type must be one of LRS, ZRS, GRS, RAGRS, GZRS, or RAGZRS."
  }
}

variable "tags" {
  description = "Additional tags. Resource-group tags and standard application/management tags are applied automatically."
  type        = map(string)
  default     = {}
}
