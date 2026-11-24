variable "resource_group_name" {
  description = "Name of the application's existing resource group in the deployment subscription. Its Azure region is used for the storage account."
  type        = string
  nullable    = false

  validation {
    condition     = length(var.resource_group_name) >= 1 && length(var.resource_group_name) <= 90 && can(regex("^[\\p{L}\\p{N}_.()-]+$", var.resource_group_name)) && !endswith(var.resource_group_name, ".")
    error_message = "Use a valid Azure resource group name (1–90 characters; no trailing period)."
  }
}

variable "application_principal_id" {
  description = "Entra object (principal) ID of the application's service principal or managed identity, not its client/application ID."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("(?i)^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", var.application_principal_id))
    error_message = "Supply the application's Entra principal (object) ID as a UUID."
  }
}

variable "private_endpoint_subnet_id" {
  description = "Resource ID of the platform-provided private endpoint subnet reachable from the app."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("(?i)^/subscriptions/[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}/resourceGroups/[^/]+/providers/Microsoft\\.Network/virtualNetworks/[^/]+/subnets/[^/]+$", var.private_endpoint_subnet_id))
    error_message = "Supply the full Azure resource ID of the private endpoint subnet."
  }
}

variable "blob_private_dns_zone_id" {
  description = "Resource ID of the platform-managed privatelink.blob.core.windows.net zone used by the application's DNS resolvers."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("(?i)^/subscriptions/[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}/resourceGroups/[^/]+/providers/Microsoft\\.Network/privateDnsZones/privatelink\\.blob\\.core\\.windows\\.net$", var.blob_private_dns_zone_id))
    error_message = "Supply the full Azure resource ID of the privatelink.blob.core.windows.net private DNS zone."
  }
}

variable "private_endpoint_location" {
  description = "Region of the private endpoint subnet's VNet, if different from the application resource group's region."
  type        = string
  default     = null

  validation {
    condition     = var.private_endpoint_location == null ? true : length(trimspace(var.private_endpoint_location)) > 0
    error_message = "Supply a nonempty Azure region or leave private_endpoint_location unset."
  }
}

variable "container_names" {
  description = "Private blob containers to create. The module grants the application blob data access at each container's scope."
  type        = set(string)
  default     = ["app-data"]
  nullable    = false

  validation {
    condition = length(var.container_names) > 0 && alltrue([
      for name in var.container_names : try(can(regex("^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$", name)) && !strcontains(name, "--"), false)
    ])
    error_message = "Provide at least one container name. Names must be 3–63 lowercase letters, digits or single hyphens, and start and end with a letter or digit."
  }
}

variable "tags" {
  description = "Additional tags to attach to the storage account and private endpoint."
  type        = map(string)
  default     = {}
  nullable    = false
}
