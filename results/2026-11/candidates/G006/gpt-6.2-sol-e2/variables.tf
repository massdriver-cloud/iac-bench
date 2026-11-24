variable "resource_group_name" {
  description = "Name of the application's existing Azure resource group in the provider subscription. The account is created in the resource group's Azure region."
  type        = string
  nullable    = false

  validation {
    condition     = length(var.resource_group_name) <= 90 && can(regex("^[[:alnum:]_.()-]+$", var.resource_group_name)) && !endswith(var.resource_group_name, ".")
    error_message = "Use a valid Azure resource group name, up to 90 characters, that does not end with a period."
  }
}

variable "application_principal_id" {
  description = "Object (principal) ID of the application's managed identity or Entra service principal, not its client/application ID."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.application_principal_id))
    error_message = "Provide the Entra identity's object (principal) ID as a GUID."
  }
}

variable "container_names" {
  description = "Private blob containers to create. The application receives Storage Blob Data Contributor on each one. Removing a container from this set requests its deletion."
  type        = set(string)
  default     = ["app-files"]
  nullable    = false

  validation {
    condition = length(var.container_names) > 0 && alltrue([
      for name in var.container_names : try(length(name) >= 3 && length(name) <= 63 && can(regex("^[a-z0-9]+(-[a-z0-9]+)*$", name)), false)
    ])
    error_message = "Specify at least one container name. Each must be 3–63 characters and use lowercase letters, digits, and single hyphens between letters or digits."
  }
}

variable "replication_type" {
  description = "Storage redundancy. Keep ZRS for zone resilience; choose LRS only where ZRS is unavailable or the workload can accept single-location redundancy."
  type        = string
  default     = "ZRS"
  nullable    = false

  validation {
    condition     = contains(["ZRS", "LRS"], var.replication_type)
    error_message = "replication_type must be ZRS or LRS."
  }
}

variable "private_endpoint" {
  description = "Optional private-only access. Supply an existing subnet and the existing privatelink.blob.core.windows.net private DNS zone. Set location if the subnet's virtual network is in a different Azure region from the account."
  type = object({
    subnet_id           = string
    private_dns_zone_id = string
    location            = optional(string)
  })
  default = null

  validation {
    condition = var.private_endpoint == null ? true : (
      can(regex("(?i)^/subscriptions/[^/]+/resourcegroups/[^/]+/providers/microsoft\\.network/virtualnetworks/[^/]+/subnets/[^/]+$", var.private_endpoint.subnet_id)) &&
      can(regex("(?i)^/subscriptions/[^/]+/resourcegroups/[^/]+/providers/microsoft\\.network/privatednszones/privatelink\\.blob\\.core\\.windows\\.net$", var.private_endpoint.private_dns_zone_id)) &&
      (var.private_endpoint.location == null ? true : trimspace(var.private_endpoint.location) != "")
    )
    error_message = "Provide a subnet resource ID and a resource ID for the privatelink.blob.core.windows.net private DNS zone, plus a nonempty Azure region if location is set."
  }
}

variable "tags" {
  description = "Additional Azure resource tags for the storage account and optional private endpoint."
  type        = map(string)
  default     = {}
  nullable    = false
}
