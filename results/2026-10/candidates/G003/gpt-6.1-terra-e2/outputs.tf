output "app_id" {
  description = "Resource ID of the production app."
  value       = azurerm_linux_web_app.service.id
}

output "url" {
  description = "Default HTTPS URL of the production app."
  value       = "https://${azurerm_linux_web_app.service.default_hostname}"
}

output "principal_id" {
  description = "Production app system-assigned identity principal ID."
  value       = azurerm_linux_web_app.service.identity[0].principal_id
}

output "service_plan_id" {
  value = azurerm_service_plan.service.id
}

output "log_analytics_workspace_id" {
  value = azurerm_log_analytics_workspace.service.id
}

output "application_insights_id" {
  value = azurerm_application_insights.service.id
}

output "staging_url" {
  value = var.enable_staging_slot ? "https://${azurerm_linux_web_app_slot.staging[0].default_hostname}" : null
}

output "staging_principal_id" {
  value = var.enable_staging_slot ? azurerm_linux_web_app_slot.staging[0].identity[0].principal_id : null
}
