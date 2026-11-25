output "web_app_id" {
  description = "Resource ID of the App Service."
  value       = azurerm_linux_web_app.this.id
}

output "web_app_name" {
  description = "Name of the App Service."
  value       = azurerm_linux_web_app.this.name
}

output "default_hostname" {
  description = "Production hostname of the service."
  value       = azurerm_linux_web_app.this.default_hostname
}

output "identity_principal_id" {
  description = "Object ID of the app's system-assigned managed identity (use it to grant the service access to databases, Key Vault, Service Bus, etc.)."
  value       = azurerm_linux_web_app.this.identity[0].principal_id
}

output "service_plan_id" {
  description = "Resource ID of the App Service plan."
  value       = azurerm_service_plan.this.id
}

output "staging_slot_hostname" {
  description = "Hostname of the staging slot, or null when the slot is disabled."
  value       = var.staging_slot_enabled ? azurerm_linux_web_app_slot.staging[0].default_hostname : null
}

output "application_insights_connection_string" {
  description = "Connection string the app uses to send telemetry (already injected as an app setting)."
  value       = azurerm_application_insights.this.connection_string
  sensitive   = true
}

output "application_insights_instrumentation_key" {
  description = "Legacy instrumentation key, for SDKs that still require it."
  value       = azurerm_application_insights.this.instrumentation_key
  sensitive   = true
}

output "log_analytics_workspace_id" {
  description = "Resource ID of the Log Analytics workspace receiving logs and metrics."
  value       = azurerm_log_analytics_workspace.this.id
}
