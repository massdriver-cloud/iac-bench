variable "resource_group_name" {
  description = "Name of the application's existing resource group. The account is deployed in the group's Azure region."
  type        = string
  nullable    = false

  validation {
    condition     = length(trimspace(var.resource_group_name)) > 0 && var.resource_group_name == trimspace(var.resource_group_name)
    error_message = "Supply a non-empty resource group name without leading or trailing whitespace."
  }
}

variable "application_principal_id" {
  description = "Object (principal) ID of the application's existing Entra service principal or managed identity. Do not use its application/client ID."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$", var.application_principal_id))
    error_message = "Supply the application's principal/object ID as a UUID."
  }
}

variable "container_names" {
  description = "Private blob containers to create and give the application access to. Removing a name removes that container from management by destroying it."
  type        = set(string)
  default     = ["app-data"]
  nullable    = false

  validation {
    condition = length(var.container_names) > 0 && alltrue([
      for name in var.container_names : can(regex("^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$", name)) && !strcontains(name, "--")
    ])
    error_message = "Supply at least one container name; each must have 3–63 lowercase letters, digits or hyphens, start and end with a letter or digit, and have no consecutive hyphens."
  }
}

variable "replication_type" {
  description = "Storage redundancy. LRS is the low-cost baseline; choose ZRS for zone redundancy or a geo-redundant option if required and supported in the region."
  type        = string
  default     = "LRS"
  nullable    = false

  validation {
    condition     = contains(["LRS", "ZRS", "GRS", "RAGRS", "GZRS", "RAGZRS"], var.replication_type)
    error_message = "Use LRS, ZRS, GRS, RAGRS, GZRS, or RAGZRS."
  }
}

variable "private_network" {
  description = "Optional private-only Blob access. Supply an existing private endpoint subnet and privatelink.blob.core.windows.net zone. App networks must already have routing and DNS resolution to them."
  type = object({
    subnet_id           = string
    private_dns_zone_id = string
  })
  default = null

  validation {
    condition = var.private_network == null ? true : (
      can(regex("(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.Network/virtualNetworks/[^/]+/subnets/[^/]+$", var.private_network.subnet_id)) &&
      can(regex("(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.Network/privateDnsZones/privatelink\\.blob\\.core\\.windows\\.net$", var.private_network.private_dns_zone_id))
    )
    error_message = "Supply the full Azure resource IDs for the endpoint subnet and the privatelink.blob.core.windows.net private DNS zone."
  }
}

variable "tags" {
  description = "Additional resource tags; matching keys override tags inherited from the resource group."
  type        = map(string)
  default     = {}
  nullable    = false
}
