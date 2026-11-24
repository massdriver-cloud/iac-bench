variable "acr_resource_id" {
  description = "Optional resource ID of an Azure Container Registry using registry-level RBAC. Grants a user-assigned identity AcrPull and uses it for image pulls; registry URL must point to that registry."
  type        = string
  default     = null
}
