variable "application_name" {
  type        = string
  description = "The name of the application (e.g., 'orders')."
}

variable "environment" {
  type        = string
  description = "The environment name (e.g., 'staging', 'prod')."
}

variable "resource_group_name" {
  type        = string
  description = "The name of the resource group where the storage account will be deployed."
}

variable "location" {
  type        = string
  description = "The Azure region where the storage account will be created."
}

variable "application_principal_ids" {
  type        = list(string)
  description = "List of Principal IDs (Object IDs) for the application's identities. They will be granted 'Storage Blob Data Contributor' access."
  default     = []
}

variable "containers" {
  type        = list(string)
  description = "List of blob container names to create in the storage account."
  default     = ["uploads"]
}
