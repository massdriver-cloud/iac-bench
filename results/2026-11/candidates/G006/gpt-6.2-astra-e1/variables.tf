variable "resource_group_name" {
  type        = string
  nullable    = false
  description = "Existing application environment resource group in the deployment subscription."
  validation {
    condition     = length(trimspace(var.resource_group_name)) > 0
    error_message = "Enter the name of an existing resource group."
  }
}

variable "app_principal_id" {
  type        = string
  nullable    = false
  description = "Entra object (principal) ID of the application's managed identity or service principal, not its client ID."
  validation {
    condition     = can(regex("(?i)^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", var.app_principal_id))
    error_message = "Enter the application's principal object ID as a UUID."
  }
}
