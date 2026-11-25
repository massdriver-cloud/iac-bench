variable "resource_group_name" {
  description = "Existing application resource group in the target subscription (one account per group)."
  type        = string
  nullable    = false
}

variable "app_principal_id" {
  description = "Entra service principal object ID of the application's identity, not its client ID."
  type        = string
  nullable    = false
  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.app_principal_id))
    error_message = "Supply the application identity's principal/object ID as a UUID."
  }
}
