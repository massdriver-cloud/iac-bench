variable "resource_group_name" {
  description = "Name of the application's existing resource group in this environment. Its location and tags are inherited."
  type        = string
  nullable    = false

  validation {
    condition     = length(trimspace(var.resource_group_name)) > 0
    error_message = "Provide the name of an existing application resource group."
  }
}

variable "storage_account_name" {
  description = "Globally unique storage account name: 3-24 lowercase letters or digits. Use a separate name for each environment."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-z0-9]{3,24}$", var.storage_account_name))
    error_message = "The account name must contain 3-24 lowercase letters or digits only."
  }
}

variable "application_principal_id" {
  description = "Entra object (principal) ID of the application's existing managed identity or service principal; NOT its client/application ID."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.application_principal_id))
    error_message = "Provide the application's Entra principal/object ID as a UUID."
  }
}

variable "containers" {
  description = "Private Blob containers to create. The application receives read/write/delete access only to these containers."
  type        = set(string)
  default     = ["files"]
  nullable    = false

  validation {
    condition = length(var.containers) > 0 && alltrue([
      for name in var.containers : length(name) >= 3 && length(name) <= 63 && can(regex("^[a-z0-9]+(-[a-z0-9]+)*$", name))
    ])
    error_message = "Provide at least one container; names must be 3-63 lowercase letters, digits or single interior hyphens."
  }
}

variable "replication_type" {
  description = "ZRS by default for resilience to an availability-zone failure. LRS is a cheaper non-zone-resilient option; GZRS adds asynchronous regional replication. Confirm regional availability. Changing this may require migration/replacement."
  type        = string
  default     = "ZRS"
  nullable    = false

  validation {
    condition     = contains(["LRS", "ZRS", "GRS", "RAGRS", "GZRS", "RAGZRS"], var.replication_type)
    error_message = "Use LRS, ZRS, GRS, RAGRS, GZRS or RAGZRS."
  }
}

variable "network_access" {
  description = "Optional public-endpoint firewall allowlist. Null permits authenticated access from any network (works with AKS and App Service without network prerequisites). Subnets must already enable the Microsoft.Storage service endpoint; IPs must be public IPv4 addresses/CIDRs. This is not Private Link."
  type = object({
    ip_rules   = optional(set(string), [])
    subnet_ids = optional(set(string), [])
  })
  default = null

  validation {
    condition     = var.network_access == null ? true : length(var.network_access.ip_rules) + length(var.network_access.subnet_ids) > 0
    error_message = "Supply at least one permitted IP or subnet, or use null for unrestricted authenticated network access."
  }
}

variable "tags" {
  description = "Additional tags, overriding inherited resource group tags with the same key."
  type        = map(string)
  default     = {}
  nullable    = false
}
