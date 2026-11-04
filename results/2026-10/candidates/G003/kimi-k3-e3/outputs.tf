output "hostname" {
  description = "Default hostname of the production app."
  value       = azurerm_linux_web_app.this.default_hostname
}

output "staging_slot_hostname" {
  description = "Default hostname of the staging slot (null when the slot is disabled)."
  value       = var.deployment_slot_enabled ? azurerm_linux_web_app_slot.staging[0].default_hostname : null
}

output "app_service_id" {
  description = "Resource ID of the web app."
  value       = azurerm_linux_web_app.this.id
}

output "principal_id" {
  description = "Object ID of the app's system-assigned managed identity (for granting access to databases, Key Vault, Service Bus, ...)."
  value       = azurerm_linux_web_app.this.identity[0].principal_id
}

output "staging_slot_principal_id" {
  description = "Object ID of the staging slot's system-assigned managed identity (null when the slot is disabled)."
  value       = var.deployment_slot_enabled ? azurerm_linux_web_app_slot.staging[0].identity[0].principal_id : null
}

output "service_plan_id" {
  description = "Resource ID of the App Service plan."
  value       = azurerm_service_plan.this.id
}

output "resource_group_name" {
  description = "Name of the resource group the module created."
  value       = azurerm_resource_group.this.name
}

output "application_insights_connection_string" {
  description = "Application Insights connection string (also injected into the app as APPLICATIONINSIGHTS_CONNECTION_STRING)."
  value       = azurerm_application_insights.this.connection_string
  sensitive   = true
}

output "log_analytics_workspace_id" {
  description = "Resource ID of the Log Analytics workspace receiving diagnostics."
  value       = local.log_analytics_workspace_id
}
