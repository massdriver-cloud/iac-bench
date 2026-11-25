output "resource_group_name" {
  description = "Resource group containing all resources for this service."
  value       = azurerm_resource_group.this.name
}

output "app_name" {
  description = "Name of the production web app."
  value       = azurerm_linux_web_app.this.name
}

output "app_id" {
  description = "Resource ID of the production web app."
  value       = azurerm_linux_web_app.this.id
}

output "default_hostname" {
  description = "Default *.azurewebsites.net hostname of the production app."
  value       = azurerm_linux_web_app.this.default_hostname
}

output "app_url" {
  description = "Base URL of the production app."
  value       = "https://${azurerm_linux_web_app.this.default_hostname}"
}

output "staging_slot_hostname" {
  description = "Hostname of the staging slot (null when staging_slot_enabled is false)."
  value       = try(azurerm_linux_web_app_slot.staging[0].default_hostname, null)
}

output "staging_slot_url" {
  description = "Base URL of the staging slot (null when staging_slot_enabled is false)."
  value       = try("https://${azurerm_linux_web_app_slot.staging[0].default_hostname}", null)
}

output "service_plan_id" {
  description = "Resource ID of the App Service Plan carrying this service."
  value       = azurerm_service_plan.this.id
}

output "application_insights_connection_string" {
  description = "Application Insights connection string, already injected into the app as APPLICATIONINSIGHTS_CONNECTION_STRING. Use it to instrument the service itself."
  value       = azurerm_application_insights.this.connection_string
  sensitive   = true
}

output "log_analytics_workspace_id" {
  description = "Log Analytics workspace receiving this service's logs and metrics."
  value       = local.log_analytics_workspace_id
}

output "managed_identity_principal_id" {
  description = "Object ID of the app's system-assigned managed identity (null when disabled). Grant this principal AcrPull on private registries or Key Vault access as needed."
  value       = try(azurerm_linux_web_app.this.identity[0].principal_id, null)
}
