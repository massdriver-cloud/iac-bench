output "app_id" {
  description = "Production App Service resource ID."
  value       = azurerm_linux_web_app.this.id
}

output "app_url" {
  description = "Production HTTPS endpoint."
  value       = "https://${azurerm_linux_web_app.this.default_hostname}"
}

output "app_identity_principal_id" {
  description = "Production system-assigned identity principal ID."
  value       = azurerm_linux_web_app.this.identity[0].principal_id
}

output "staging_url" {
  description = "Staging slot HTTPS endpoint, if enabled."
  value       = var.staging_slot_enabled ? "https://${azurerm_linux_web_app_slot.staging[0].default_hostname}" : null
}

output "staging_identity_principal_id" {
  description = "Staging system-assigned identity principal ID, if enabled."
  value       = var.staging_slot_enabled ? azurerm_linux_web_app_slot.staging[0].identity[0].principal_id : null
}

output "service_plan_id" {
  description = "App Service plan resource ID."
  value       = azurerm_service_plan.this.id
}

output "log_analytics_workspace_id" {
  description = "Log Analytics workspace resource ID."
  value       = azurerm_log_analytics_workspace.this.id
}

output "application_insights_connection_string" {
  description = "Application Insights connection string for application instrumentation."
  value       = azurerm_application_insights.this.connection_string
  sensitive   = true
}
