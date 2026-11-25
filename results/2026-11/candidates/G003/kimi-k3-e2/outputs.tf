output "resource_group_name" {
  description = "Name of the resource group the service lives in."
  value       = local.resource_group_name
}

output "service_plan_id" {
  description = "Resource ID of the App Service plan."
  value       = azurerm_service_plan.this.id
}

output "app_service_name" {
  description = "Name of the deployed web app."
  value       = azurerm_linux_web_app.this.name
}

output "app_service_id" {
  description = "Resource ID of the deployed web app."
  value       = azurerm_linux_web_app.this.id
}

output "default_hostname" {
  description = "Production hostname of the service."
  value       = azurerm_linux_web_app.this.default_hostname
}

output "principal_id" {
  description = "Object ID of the app's system-assigned managed identity (e.g. for granting Key Vault or database access)."
  value       = azurerm_linux_web_app.this.identity[0].principal_id
}

output "staging_slot_hostname" {
  description = "Hostname of the staging slot, when enabled."
  value       = var.staging_slot_enabled ? azurerm_linux_web_app_slot.this[0].default_hostname : null
}

output "application_insights_connection_string" {
  description = "Application Insights connection string (also injected into the app as APPLICATIONINSIGHTS_CONNECTION_STRING)."
  value       = azurerm_application_insights.this.connection_string
  sensitive   = true
}

output "log_analytics_workspace_id" {
  description = "Resource ID of the Log Analytics workspace receiving logs and metrics."
  value       = local.workspace_id
}
