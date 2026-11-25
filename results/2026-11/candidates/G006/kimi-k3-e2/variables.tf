variable "name" {
  type        = string
  description = "Globally unique name for the storage account: 3-24 characters, lowercase letters and digits only (no hyphens), e.g. \"stordersprod01\"."

  validation {
    condition     = can(regex("^[a-z0-9]{3,24}$", var.name))
    error_message = "The storage account name must be 3-24 characters of lowercase letters and digits only."
  }
}

variable "resource_group_name" {
  type        = string
  description = "Name of the application's existing resource group, e.g. \"orders-staging\". The storage account belongs to the application, so it is created here. The resource group is not managed by this module."
}

variable "identity_principal_id" {
  type        = string
  description = "Object ID of the application's existing Entra ID identity (managed identity or service principal). It is granted Storage Blob Data Contributor on the account, so the application authenticates with its identity and never needs access keys, SAS tokens or connection strings."

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$", var.identity_principal_id))
    error_message = "identity_principal_id must be a GUID: the identity's object ID (not its client/application ID)."
  }
}

variable "location" {
  type        = string
  default     = null
  description = "Azure region for the storage account. Defaults to the region of the application's resource group, which is the right choice for almost every application."
}

variable "containers" {
  type        = set(string)
  default     = []
  description = "Blob containers to create for the application, e.g. [\"uploads\", \"media\", \"reports\"]. All containers are private; public access is disabled at the account level."

  validation {
    condition     = alltrue([for c in var.containers : can(regex("^[a-z0-9]([a-z0-9-]{1,61}[a-z0-9])?$", c))])
    error_message = "Container names must be 3-63 characters of lowercase letters, digits and hyphens, starting and ending with a letter or digit."
  }
}

variable "account_replication_type" {
  type        = string
  default     = "LRS"
  description = "Data redundancy. \"LRS\" (default) is the cost-effective choice for most application data. Use \"ZRS\" or \"GRS\" when the data is hard to recreate and needs zone or region level durability."

  validation {
    condition     = contains(["LRS", "ZRS", "GRS", "RAGRS", "GZRS", "RAGZRS"], var.account_replication_type)
    error_message = "account_replication_type must be one of LRS, ZRS, GRS, RAGRS, GZRS, RAGZRS."
  }
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags applied to the storage account, e.g. { application = \"orders\", environment = \"staging\" }."
}
