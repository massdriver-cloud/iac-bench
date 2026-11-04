output "resource_group_name" {
  description = "Name of the created resource group."
  value       = azurerm_resource_group.rg.name
}

output "app_service_plan_id" {
  description = "ID of the App Service Plan."
  value       = azurerm_service_plan.asp.id
}

output "web_app_id" {
  description = "ID of the primary Web App."
  value       = azurerm_linux_web_app.app.id
}

output "web_app_default_hostname" {
  description = "Default hostname of the primary Web App."
  value       = azurerm_linux_web_app.app.default_hostname
}

output "staging_slot_default_hostname" {
  description = "Default hostname of the staging slot, if enabled."
  value       = var.enable_staging_slot ? azurerm_linux_web_app_slot.staging[0].default_hostname : null
}

output "application_insights_id" {
  description = "ID of the Application Insights instance."
  value       = azurerm_application_insights.appinsights.id
}

output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics Workspace."
  value       = azurerm_log_analytics_workspace.law.id
}
