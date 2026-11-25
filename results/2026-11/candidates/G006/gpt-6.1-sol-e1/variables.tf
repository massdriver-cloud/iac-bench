variable "resource_group_name" {
  description = "Name of the application's EXISTING resource group. Storage inherits its location."
  type        = string
  validation {
    condition     = length(trimspace(var.resource_group_name)) > 0
    error_message = "Supply the existing application resource group name."
  }
}

variable "storage_account_name" {
  description = "Globally unique storage account name: 3–24 lowercase letters or digits."
  type        = string
  validation {
    condition     = can(regex("^[a-z0-9]{3,24}$", var.storage_account_name))
    error_message = "Use 3–24 lowercase letters or digits."
  }
}

variable "application_principal_id" {
  description = "Entra object (principal) ID of the app's existing managed identity or service principal, NOT its client/application ID."
  type        = string
  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.application_principal_id))
    error_message = "Supply the application's Entra principal object ID as a UUID."
  }
}

variable "containers" {
  description = "Private blob containers, each granting the app read/write/delete access. Renaming a container destroys the old one; migrate data first."
  type        = set(string)
  default     = ["files"]
  validation {
    condition = length(var.containers) > 0 && alltrue([
      for name in var.containers : can(regex("^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$", name)) && !strcontains(name, "--")
    ])
    error_message = "Specify at least one container, each 3–63 lowercase letters/digits/hyphens, starting and ending with a letter/digit, with no consecutive hyphens."
  }
}

variable "replication_type" {
  description = "Standard-tier replication. ZRS protects against a zone failure; choose LRS only when its lower durability is acceptable or ZRS is unavailable. GZRS/GRS add asynchronous regional copies."
  type        = string
  default     = "ZRS"
  validation {
    condition     = contains(["LRS", "ZRS", "GRS", "RAGRS", "GZRS", "RAGZRS"], var.replication_type)
    error_message = "Choose LRS, ZRS, GRS, RAGRS, GZRS, or RAGZRS."
  }
}

variable "recovery_days" {
  description = "Blob/container soft-delete retention, also used to expire previous blob versions. Current blobs are never automatically deleted."
  type        = number
  default     = 30
  validation {
    condition     = var.recovery_days >= 1 && var.recovery_days <= 365 && floor(var.recovery_days) == var.recovery_days
    error_message = "Use a whole number of days between 1 and 365."
  }
}

variable "private_endpoint" {
  description = "Optional private-only blob access. Supply an existing private-endpoint subnet and existing privatelink.blob.core.windows.net private DNS zone IDs linked to app networks. This disables the public data endpoint."
  type = object({
    subnet_id            = string
    private_dns_zone_ids = set(string)
  })
  default = null
  validation {
    condition = var.private_endpoint == null ? true : (
      can(regex("(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft.Network/virtualNetworks/[^/]+/subnets/[^/]+$", var.private_endpoint.subnet_id)) &&
      length(var.private_endpoint.private_dns_zone_ids) > 0 && alltrue([
        for id in var.private_endpoint.private_dns_zone_ids : can(regex("(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft.Network/privateDnsZones/privatelink\\.blob\\.core\\.windows\\.net$", id))
      ])
    )
    error_message = "Supply a subnet resource ID and at least one privatelink.blob.core.windows.net private DNS zone resource ID."
  }
}

variable "tags" {
  description = "Application ownership, environment and cost allocation tags, merged over the resource group's tags."
  type        = map(string)
  default     = {}
}
