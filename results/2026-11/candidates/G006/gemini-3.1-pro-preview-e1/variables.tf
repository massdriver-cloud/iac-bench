variable "application_name" {
  type        = string
  description = "The name of the application. Used to generate the storage account name."
}

variable "environment" {
  type        = string
  description = "The environment (e.g., staging, prod). Used to generate the storage account name."
}

variable "resource_group_name" {
  type        = string
  description = "The name of the resource group where the storage account should be created."
}

variable "location" {
  type        = string
  description = "The Azure region to deploy the storage account."
}

variable "app_identity_principal_id" {
  type        = string
  description = "The principal ID of the application's Entra ID identity to be granted access to the storage account."
}

variable "containers" {
  type        = set(string)
  description = "Set of containers to create in the storage account."
  default     = ["uploads", "images", "videos", "reports", "exports"]
}
