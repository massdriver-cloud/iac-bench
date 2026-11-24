output "app_id" {
  description = "Production web app resource ID."
  value       = azurerm_linux_web_app.service.id
}

output "app_url" {
  description = "Production HTTPS endpoint."
  value       = "https://${azurerm_linux_web_app.service.default_hostname}"
}

output "app_principal_id" {
  description = "System-assigned identity principal ID for application access to Azure resources."
  value       = azurerm_linux_web_app.service.identity[0].principal_id
}

output "staging_url" {
  description = "Staging slot HTTPS endpoint when enabled."
  value       = var.enable_staging_slot ? "https://${azurerm_linux_web_app_slot.staging[0].default_hostname}" : null
}

output "staging_principal_id" {
  description = "Staging slot system-assigned identity principal ID when enabled."
  value       = var.enable_staging_slot ? azurerm_linux_web_app_slot.staging[0].identity[0].principal_id : null
}

output "application_insights_id" {
  value       = azurerm_application_insights.service.id
  description = "Application Insights resource ID."
}

output "log_analytics_workspace_id" {
  value       = azurerm_log_analytics_workspace.service.id
  description = "Log Analytics workspace resource ID."
}
