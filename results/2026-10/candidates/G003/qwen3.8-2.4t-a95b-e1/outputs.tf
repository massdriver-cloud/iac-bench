output "resource_group_name" {
  description = "Resource group created for the service."
  value       = azurerm_resource_group.this.name
}

output "app_service_id" {
  description = "Resource ID of the web app."
  value       = azurerm_linux_web_app.this.id
}

output "app_service_name" {
  description = "Name of the web app."
  value       = azurerm_linux_web_app.this.name
}

output "default_hostname" {
  description = "Default *.azurewebsites.net hostname of the production app."
  value       = azurerm_linux_web_app.this.default_hostname
}

output "url" {
  description = "HTTPS URL of the production app."
  value       = "https://${azurerm_linux_web_app.this.default_hostname}"
}

output "staging_slot_hostname" {
  description = "Hostname of the staging slot, or null when the slot is disabled."
  value       = var.staging_slot_enabled ? azurerm_linux_web_app_slot.staging[0].default_hostname : null
}

output "staging_slot_name" {
  description = "Name of the staging slot, or null when the slot is disabled."
  value       = var.staging_slot_enabled ? azurerm_linux_web_app_slot.staging[0].name : null
}

output "service_plan_id" {
  description = "Resource ID of the App Service Plan backing the service."
  value       = azurerm_service_plan.this.id
}

output "app_insights_connection_string" {
  description = "Application Insights connection string (already injected into the app as APPLICATIONINSIGHTS_CONNECTION_STRING)."
  value       = azurerm_application_insights.this.connection_string
  sensitive   = true
}

output "app_insights_instrumentation_key" {
  description = "Application Insights instrumentation key (legacy; prefer the connection string)."
  value       = azurerm_application_insights.this.instrumentation_key
  sensitive   = true
}

output "log_analytics_workspace_id" {
  description = "Log Analytics workspace receiving logs and metrics (created by the module or supplied by the caller)."
  value       = local.law_workspace_id
}

output "system_identity_principal_id" {
  description = "Principal ID of the web app's system-assigned managed identity."
  value       = azurerm_linux_web_app.this.identity[0].principal_id
}
