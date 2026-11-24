locals {
  # Derive these from the resources, rather than directly from the input, so
  # consumers of the outputs also depend on successful container creation.
  provisioned_container_names = sort(keys(azapi_resource.containers))
}

output "storage_account_id" {
  description = "Resource ID of the application storage account."
  value       = azurerm_storage_account.this.id
}

output "storage_account_name" {
  description = "Globally unique name of the application storage account."
  value       = azurerm_storage_account.this.name
}

output "primary_blob_endpoint" {
  description = "HTTPS blob endpoint to use with an Azure Storage SDK and the application's Entra ID identity."
  value       = azurerm_storage_account.this.primary_blob_endpoint
}

output "container_names" {
  description = "Sorted names of the private containers available to the application."
  value       = local.provisioned_container_names
}

output "container_ids" {
  description = "Map of container name to Azure resource ID."
  value = {
    for name, container in azapi_resource.containers : name => container.id
  }
}

output "role_assignment_id" {
  description = "ID of the application's Storage Blob Data Contributor role assignment."
  value       = azurerm_role_assignment.application_blob_data.id
}

output "application_access" {
  description = "Non-secret connection information for application configuration. Its resource dependencies include both container creation and the application's role assignment."
  value = {
    blob_endpoint               = azurerm_storage_account.this.primary_blob_endpoint
    containers                  = local.provisioned_container_names
    authentication              = "Microsoft Entra ID"
    application_identity_object = var.application_identity_object_id
    assigned_role               = azurerm_role_assignment.application_blob_data.role_definition_name
    role_assignment_id          = azurerm_role_assignment.application_blob_data.id
  }
}
