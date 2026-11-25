output "resource_group_name" {
  description = "Resource group containing the service resources."
  value       = azurerm_resource_group.service.name
}

output "app_service_name" {
  description = "Name of the Linux Web App."
  value       = azurerm_linux_web_app.service.name
}

output "app_service_default_hostname" {
  description = "Default Azure hostname for the Web App."
  value       = azurerm_linux_web_app.service.default_hostname
}

output "app_service_id" {
  description = "Resource ID of the Linux Web App."
  value       = azurerm_linux_web_app.service.id
}

output "app_service_principal_id" {
  description = "Principal ID of the Web App's system-assigned managed identity."
  value       = azurerm_linux_web_app.service.identity[0].principal_id
}

output "service_plan_id" {
  description = "Resource ID of the App Service plan."
  value       = azurerm_service_plan.service.id
}

output "application_insights_connection_string" {
  description = "Connection string for Application Insights instrumentation."
  value       = azurerm_application_insights.service.connection_string
  sensitive   = true
}

output "log_analytics_workspace_id" {
  description = "Resource ID of the Log Analytics workspace."
  value       = azurerm_log_analytics_workspace.service.id
}
