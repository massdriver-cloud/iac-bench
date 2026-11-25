output "resource_group_name" {
  description = "Name of the resource group containing the App Service"
  value       = local.rg_name
}

output "service_plan_id" {
  description = "Resource ID of the App Service Plan"
  value       = azurerm_service_plan.this.id
}

output "app_service_id" {
  description = "Resource ID of the App Service Web App"
  value       = azurerm_linux_web_app.this.id
}

output "app_service_name" {
  description = "Name of the App Service Web App"
  value       = azurerm_linux_web_app.this.name
}

output "default_hostname" {
  description = "Default hostname of the primary web app"
  value       = azurerm_linux_web_app.this.default_hostname
}

output "app_service_principal_id" {
  description = "System-assigned managed identity principal ID for the web app"
  value       = azurerm_linux_web_app.this.identity[0].principal_id
}

output "staging_slot_name" {
  description = "Name of the staging deployment slot"
  value       = var.enable_staging_slot ? azurerm_linux_web_app_slot.staging[0].name : null
}

output "staging_slot_hostname" {
  description = "Default hostname of the staging deployment slot"
  value       = var.enable_staging_slot ? azurerm_linux_web_app_slot.staging[0].default_hostname : null
}

output "application_insights_id" {
  description = "Resource ID of the Application Insights instance"
  value       = var.enable_app_insights ? azurerm_application_insights.this[0].id : null
}

output "application_insights_instrumentation_key" {
  description = "Instrumentation key for Application Insights"
  value       = local.app_insights_key
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "Connection string for Application Insights"
  value       = local.app_insights_connection
  sensitive   = true
}
