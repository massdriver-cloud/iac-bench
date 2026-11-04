output "resource_group_name" {
  value       = local.resource_group_name
  description = "The name of the resource group"
}

output "service_plan_id" {
  value       = local.service_plan_id
  description = "The ID of the App Service Plan"
}

output "app_service_id" {
  value       = azurerm_linux_web_app.this.id
  description = "The ID of the Linux Web App"
}

output "app_service_name" {
  value       = azurerm_linux_web_app.this.name
  description = "The name of the Linux Web App"
}

output "default_hostname" {
  value       = azurerm_linux_web_app.this.default_hostname
  description = "The default hostname of the Linux Web App"
}

output "principal_id" {
  value       = one(azurerm_linux_web_app.this.identity[*].principal_id)
  description = "The System-Assigned Managed Identity Principal ID for the Web App"
}

output "staging_slot_id" {
  value       = one(azurerm_linux_web_app_slot.staging[*].id)
  description = "The ID of the staging deployment slot"
}

output "staging_slot_default_hostname" {
  value       = one(azurerm_linux_web_app_slot.staging[*].default_hostname)
  description = "The default hostname of the staging deployment slot"
}

output "application_insights_id" {
  value       = one(azurerm_application_insights.this[*].id)
  description = "The ID of the created Application Insights instance"
}

output "application_insights_connection_string" {
  value       = local.app_insights_connection_string
  sensitive   = true
  description = "Application Insights connection string"
}

output "application_insights_instrumentation_key" {
  value       = local.app_insights_instrumentation_key
  sensitive   = true
  description = "Application Insights instrumentation key"
}

output "log_analytics_workspace_id" {
  value       = local.log_analytics_workspace_id
  description = "The Log Analytics Workspace ID used for diagnostics"
}
