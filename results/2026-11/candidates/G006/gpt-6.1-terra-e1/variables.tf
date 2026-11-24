variable "resource_group_name" {
  description = "Name of the application's existing resource group."
  type        = string

  validation {
    condition     = length(trimspace(var.resource_group_name)) > 0
    error_message = "resource_group_name must not be empty."
  }
}

variable "location" {
  description = "Azure region of the existing resource group, for example eastus."
  type        = string

  validation {
    condition     = length(trimspace(var.location)) > 0
    error_message = "location must not be empty."
  }
}

variable "storage_account_name" {
  description = "Globally unique Azure storage account name: 3-24 lowercase letters and digits."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{3,24}$", var.storage_account_name))
    error_message = "storage_account_name must be 3-24 lowercase letters and digits."
  }
}

variable "application_principal_id" {
  description = "Entra object (principal) ID of the application's managed identity or service principal, not its client ID."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.application_principal_id))
    error_message = "application_principal_id must be a UUID object ID."
  }
}

variable "container_name" {
  description = "Name of the private blob container provided to the application."
  type        = string
  default     = "app-data"

  validation {
    condition     = length(var.container_name) >= 3 && length(var.container_name) <= 63 && can(regex("^[a-z0-9]+(-[a-z0-9]+)*$", var.container_name))
    error_message = "container_name must be 3-63 lowercase letters, digits or single hyphens, starting and ending with a letter or digit."
  }
}

variable "tags" {
  description = "Tags to apply to the storage account."
  type        = map(string)
  default     = {}
}

variable "allowed_subnet_ids" {
  description = "Optional subnet IDs allowed to reach the public storage endpoint. Subnets need the Microsoft.Storage service endpoint. An empty list together with an empty allowed_ip_ranges leaves the endpoint publicly reachable (Entra authorization is still required)."
  type        = list(string)
  default     = []
}

variable "allowed_ip_ranges" {
  description = "Optional public IPv4 addresses or CIDR ranges allowed to reach the public storage endpoint."
  type        = list(string)
  default     = []
}
