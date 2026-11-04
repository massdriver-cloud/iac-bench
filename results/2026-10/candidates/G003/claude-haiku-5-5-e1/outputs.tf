output "resource_group_name" {
  description = "Name of the resource group holding all resources."
  value       = azurerm_resource_group.this.name
}

output "service_plan_id" {
  description = "ID of the App Service plan."
  value       = azurerm_service_plan.this.id
}

output "app_name" {
  description = "Name of the production web app."
  value       = azurerm_linux_web_app.this.name
}

output "app_default_hostname" {
  description = "Default hostname of the production app."
  value       = azurerm_linux_web_app.this.default_hostname
}

output "app_principal_id" {
  description = "Object ID of the production app's system-assigned managed identity. Grant it access (e.g. AcrPull, Key Vault) as needed."
  value       = azurerm_linux_web_app.this.identity[0].principal_id
}

output "staging_slot_default_hostname" {
  description = "Default hostname of the staging slot, or null when disabled."
  value       = var.enable_staging_slot ? azurerm_linux_web_app_slot.staging[0].default_hostname : null
}

output "autoscale_enabled" {
  description = "Whether CPU autoscale was configured for this SKU."
  value       = local.autoscale_capable
}
