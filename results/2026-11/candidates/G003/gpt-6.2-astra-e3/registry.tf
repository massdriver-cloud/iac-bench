variable "registry_identity" {
  description = "For private ACR pulls: existing user-assigned identity already authorized to pull the image. The deployer must be allowed to assign it."
  type        = object({ resource_id = string, client_id = string })
  default     = null
}
locals {
  identity_type         = var.registry_identity == null ? "SystemAssigned" : "SystemAssigned, UserAssigned"
  registry_identity_ids = var.registry_identity == null ? null : [var.registry_identity.resource_id]
}
