variable "resource_group_name" {
  description = "Name of the application's existing resource group."
  type        = string
  validation {
    condition     = length(trimspace(var.resource_group_name)) > 0
    error_message = "resource_group_name must not be empty."
  }
}

variable "location" {
  description = "Azure region for the storage account, normally the resource group's region."
  type        = string
  validation {
    condition     = length(trimspace(var.location)) > 0
    error_message = "location must not be empty."
  }
}

variable "storage_account_name" {
  description = "Globally unique Azure Storage account name: 3-24 lowercase letters and digits."
  type        = string
  validation {
    condition     = can(regex("^[a-z0-9]{3,24}$", var.storage_account_name))
    error_message = "storage_account_name must contain 3-24 lowercase letters and digits."
  }
}

variable "application_principal_id" {
  description = "Object (principal) ID of the application's existing Entra service principal or managed identity, not its client ID."
  type        = string
  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.application_principal_id))
    error_message = "application_principal_id must be an Entra object ID (UUID)."
  }
}

variable "container_name" {
  description = "Private blob container for the application."
  type        = string
  default     = "app"
  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{1,61}[a-z0-9])$", var.container_name)) && !strcontains(var.container_name, "--")
    error_message = "container_name must be 3-63 lowercase letters, digits or single hyphens, beginning and ending with a letter or digit."
  }
}

variable "replication_type" {
  description = "Storage replication. LRS is the cost-conscious default; select a supported redundant option for workloads with greater availability or disaster-recovery needs."
  type        = string
  default     = "LRS"
  validation {
    condition     = contains(["LRS", "ZRS", "GRS", "GZRS", "RAGRS", "RAGZRS"], var.replication_type)
    error_message = "replication_type must be LRS, ZRS, GRS, GZRS, RAGRS, or RAGZRS."
  }
}

variable "private_endpoint" {
  description = "Optional private Blob endpoint configuration. Supply an existing private endpoint subnet and privatelink.blob.core.windows.net private DNS zone ID; link the zone to all client VNets separately. When set, public network access is disabled."
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
    error_message = "private_endpoint must contain a subnet resource ID and the resource ID of the privatelink.blob.core.windows.net private DNS zone."
  }
}

variable "tags" {
  description = "Tags to apply to the storage account and any private endpoint."
  type        = map(string)
  default     = {}
}
