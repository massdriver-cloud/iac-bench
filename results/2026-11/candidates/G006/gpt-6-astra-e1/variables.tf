variable "resource_group_name" {
  description = "Name of the application's existing resource group. Storage uses the resource group's Azure region."
  type        = string
  nullable    = false

  validation {
    condition     = length(trimspace(var.resource_group_name)) > 0
    error_message = "Provide the name of an existing application resource group."
  }
}

variable "storage_account_name" {
  description = "Globally unique storage account name: 3-24 lowercase letters and digits. Use a different name per environment."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-z0-9]{3,24}$", var.storage_account_name))
    error_message = "Storage account names must contain 3-24 lowercase letters or digits."
  }
}

variable "application_principal_id" {
  description = "Entra object (principal) ID of the application's existing managed identity or service principal; NOT its client/application ID."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.application_principal_id))
    error_message = "application_principal_id must be the identity's UUID object ID."
  }
}

variable "containers" {
  description = "Private blob containers the application may read and write. No other containers receive application permissions."
  type        = set(string)
  default     = ["files"]
  nullable    = false

  validation {
    condition = length(var.containers) > 0 && alltrue([
      for name in var.containers : length(name) >= 3 && length(name) <= 63 && can(regex("^[a-z0-9]+(-[a-z0-9]+)*$", name))
    ])
    error_message = "Provide at least one container. Names must be 3-63 lowercase letters/digits with single internal hyphens."
  }
}

variable "replication_type" {
  description = "ZRS protects against availability-zone failure. Select LRS only for lower-cost nonproduction or regions without ZRS; GZRS adds asynchronous regional replication."
  type        = string
  default     = "ZRS"
  nullable    = false

  validation {
    condition     = contains(["LRS", "ZRS", "GZRS"], var.replication_type)
    error_message = "Choose LRS, ZRS, or GZRS. Verify availability in the resource group's region."
  }
}

variable "private_endpoint" {
  description = "Optional existing private-endpoint subnet and privatelink.blob.core.windows.net DNS zone IDs. When set, disables the public data endpoint. The DNS zone must already be linked to application VNets."
  type = object({
    subnet_id           = string
    private_dns_zone_id = string
  })
  default = null

  validation {
    condition = var.private_endpoint == null ? true : (
      can(regex("(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft.Network/virtualNetworks/[^/]+/subnets/[^/]+$", var.private_endpoint.subnet_id)) &&
      can(regex("(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft.Network/privateDnsZones/privatelink\\.blob\\.core\\.windows\\.net$", var.private_endpoint.private_dns_zone_id))
    )
    error_message = "Provide full resource IDs for an existing subnet and the privatelink.blob.core.windows.net private DNS zone."
  }
}

variable "tags" {
  description = "Additional tags; merged with tags from the existing application resource group."
  type        = map(string)
  default     = {}
  nullable    = false
}
