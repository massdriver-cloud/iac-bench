variable "resource_group_name" {
  type        = string
  description = "The name of the application's resource group."
}

variable "location" {
  type        = string
  description = "The Azure region where the storage account should be created."
}

variable "application_name" {
  type        = string
  description = "The name of the application (used to generate the storage account name)."
}

variable "environment" {
  type        = string
  description = "The deployment environment (e.g., 'staging', 'prod'). Determines replication strategy."
}

variable "app_identity_principal_id" {
  type        = string
  description = "The Object ID (Principal ID) of the application's Entra ID identity. It will be granted 'Storage Blob Data Contributor' access."
}

variable "containers" {
  type        = set(string)
  description = "A set of blob container names to create for the application."
  default     = ["uploads", "exports"]
}
