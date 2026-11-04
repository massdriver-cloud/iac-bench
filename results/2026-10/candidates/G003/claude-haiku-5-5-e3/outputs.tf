output "resource_group_name" {
  description = "Resource group containing all module resources."
  value       = azurerm_resource_group.this.name
}

output "service_plan_id" {
  description = "ID of the App Service plan."
  value       = azurerm_service_plan.this.id
}

output "web_app_id" {
  description = "ID of the production web app."
  value       = azurerm_linux_web_app.this.id
}

output "web_app_name" {
  description = "Name of the production web app."
  value       = azurerm_linux_web_app.this.name
}

output "web_app_default_hostname" {
  description = "Default hostname of the production web app."
  value       = azurerm_linux_web_app.this.default_hostname
}

output "web_app_principal_id" {
  description = "Principal ID of the production web app's system-assigned identity."
  value       = azurerm_linux_web_app.this.identity[0].principal_id
}

output "staging_slot_default_hostname" {
  description = "Default hostname of the staging slot, or null when the slot is disabled."
  value       = var.staging_slot_enabled ? azurerm_linux_web_app_slot.staging[0].default_hostname : null
}

output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics workspace receiving app logs."
  value       = azurerm_log_analytics_workspace.this.id
}

output "application_insights_connection_string" {
  description = "Application Insights connection string (already injected into the app settings)."
  value       = azurerm_application_insights.this.connection_string
  sensitive   = true
}
