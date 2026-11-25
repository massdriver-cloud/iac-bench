variable "resource_group_name" {
  description = "Name of the application's existing resource group. Storage uses this group's region."
  type        = string
  nullable    = false

  validation {
    condition     = length(trimspace(var.resource_group_name)) > 0
    error_message = "Provide the name of an existing application resource group."
  }
}

variable "storage_account_name" {
  description = "Globally unique storage account name: 3-24 lowercase letters and digits. Use a distinct name per environment."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-z0-9]{3,24}$", var.storage_account_name))
    error_message = "Storage account names must contain 3-24 lowercase letters or digits only."
  }
}

variable "application_principal_id" {
  description = "Entra object/principal ID of the application's existing managed identity or service principal; NOT its client/application ID."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.application_principal_id))
    error_message = "Provide the application's Entra principal/object ID as a UUID."
  }
}

variable "containers" {
  description = "Private blob containers to create and grant the application read/write/delete access to."
  type        = set(string)
  default     = ["app-data"]
  nullable    = false

  validation {
    condition = length(var.containers) > 0 && alltrue([
      for name in var.containers : can(regex("^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$", name)) && !strcontains(name, "--")
    ])
    error_message = "Supply at least one container. Names must be 3-63 lowercase letters, digits or single hyphens, beginning and ending with a letter or digit."
  }
}

variable "replication_type" {
  description = "ZRS (default) protects against a zone failure. LRS is a lower-cost option for disposable environments or regions without ZRS; geo-redundant options are also supported."
  type        = string
  default     = "ZRS"
  nullable    = false

  validation {
    condition     = contains(["LRS", "ZRS", "GRS", "GZRS", "RAGRS", "RAGZRS"], var.replication_type)
    error_message = "Choose LRS, ZRS, GRS, GZRS, RAGRS or RAGZRS."
  }
}

variable "tags" {
  description = "Application ownership and cost-allocation tags to add to the storage account."
  type        = map(string)
  default     = {}
  nullable    = false
}
