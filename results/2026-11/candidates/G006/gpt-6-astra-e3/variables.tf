variable "resource_group_name" {
  description = "Existing application/environment resource group. Its location is used for storage."
  type        = string
  nullable    = false
  validation {
    condition     = length(trimspace(var.resource_group_name)) > 0
    error_message = "Provide the name of an existing resource group."
  }
}

variable "storage_account_name" {
  description = "Globally unique Azure Storage account name: 3-24 lowercase letters and digits."
  type        = string
  nullable    = false
  validation {
    condition     = can(regex("^[a-z0-9]{3,24}$", var.storage_account_name))
    error_message = "Use 3-24 lowercase letters and digits; the name must be globally unique."
  }
}

variable "application_principal_id" {
  description = "Entra service principal object ID (managed identity principal_id), NOT its client/application ID. The existing application receives blob read/write/delete access to the configured containers."
  type        = string
  nullable    = false
  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.application_principal_id))
    error_message = "Provide the application service principal's UUID object ID."
  }
}

variable "container_names" {
  description = "Private blob containers to create. By default applications store their objects in files."
  type        = set(string)
  default     = ["files"]
  nullable    = false
  validation {
    condition = length(var.container_names) > 0 && alltrue([
      for name in var.container_names : length(name) >= 3 && length(name) <= 63 && can(regex("^[a-z0-9]+(-[a-z0-9]+)*$", name))
    ])
    error_message = "Supply at least one container; names must be 3-63 lowercase letters/digits with single internal hyphens."
  }
}

variable "replication_type" {
  description = "ZRS by default for zone-failure resilience. Choose LRS only where ZRS is unavailable or for lower-cost nonproduction; geo-redundant options are also supported where available."
  type        = string
  default     = "ZRS"
  nullable    = false
  validation {
    condition     = contains(["LRS", "ZRS", "GRS", "RAGRS", "GZRS", "RAGZRS"], var.replication_type)
    error_message = "Choose LRS, ZRS, GRS, RAGRS, GZRS or RAGZRS."
  }
}

variable "network_restrictions" {
  description = "Optional public endpoint firewall allowlist. Null permits authenticated traffic from any network. Subnets must have Microsoft.Storage service endpoints. IP rules must be public IPv4 addresses or CIDRs accepted by Azure Storage."
  type = object({
    ip_rules   = optional(set(string), [])
    subnet_ids = optional(set(string), [])
  })
  default = null
  validation {
    condition     = var.network_restrictions == null ? true : length(var.network_restrictions.ip_rules) + length(var.network_restrictions.subnet_ids) > 0
    error_message = "Provide at least one IP or subnet when enabling network restrictions."
  }
}

variable "tags" {
  description = "Application ownership, environment and cost allocation tags."
  type        = map(string)
  default     = {}
  nullable    = false
}
