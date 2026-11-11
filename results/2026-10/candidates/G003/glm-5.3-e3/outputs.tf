output "resource_group_name" {
  description = "Resource group the service lives in."
  value       = local.resource_group_name
}

output "service_plan_id" {
  description = "ID of the App Service plan backing the service."
  value       = azurerm_service_plan.this.id
}

output "app_service_id" {
  description = "Resource ID of the production app."
  value       = azurerm_linux_web_app.this.id
}

output "app_name" {
  description = "Globally unique name of the production app (forms the <app_name>.azurewebsites.net hostname)."
  value       = azurerm_linux_web_app.this.name
}

output "default_hostname" {
  description = "Hostname of the production app."
  value       = azurerm_linux_web_app.this.default_hostname
}

output "url" {
  description = "HTTPS URL of the production app."
  value       = "https://${azurerm_linux_web_app.this.default_hostname}"
}

output "staging_hostname" {
  description = "Hostname of the staging slot, or null when create_staging_slot = false."
  value       = one(azurerm_linux_web_app_slot.staging[*].default_hostname)
}

output "log_analytics_workspace_id" {
  description = "Log Analytics workspace collecting the service's logs and metrics."
  value       = azurerm_log_analytics_workspace.this.id
}

output "application_insights_connection_string" {
  description = "App Insights connection string (already injected into the container as APPLICATIONINSIGHTS_CONNECTION_STRING)."
  value       = azurerm_application_insights.this.connection_string
  sensitive   = true
}

output "managed_identity_principal_id" {
  description = "Object ID of the production app's system-assigned identity. Grant this AcrPull on any private registry you wire up yourself."
  value       = azurerm_linux_web_app.this.identity[0].principal_id
}
