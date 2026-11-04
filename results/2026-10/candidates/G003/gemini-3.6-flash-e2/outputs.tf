output "resource_group_name" {
  description = "Name of the resource group containing the App Service resources."
  value       = local.resource_group_name
}

output "service_plan_id" {
  description = "ID of the App Service Plan."
  value       = azurerm_service_plan.this.id
}

output "service_plan_name" {
  description = "Name of the App Service Plan."
  value       = azurerm_service_plan.this.name
}

output "web_app_id" {
  description = "ID of the Linux Web App."
  value       = azurerm_linux_web_app.this.id
}

output "web_app_name" {
  description = "Name of the Linux Web App."
  value       = azurerm_linux_web_app.this.name
}

output "web_app_default_hostname" {
  description = "Default hostname of the Linux Web App."
  value       = azurerm_linux_web_app.this.default_hostname
}

output "web_app_identity_principal_id" {
  description = "Principal ID of the System-Assigned Managed Identity for the Web App."
  value       = try(azurerm_linux_web_app.this.identity[0].principal_id, null)
}

output "web_app_identity_tenant_id" {
  description = "Tenant ID of the System-Assigned Managed Identity for the Web App."
  value       = try(azurerm_linux_web_app.this.identity[0].tenant_id, null)
}

output "staging_slot_id" {
  description = "ID of the staging deployment slot, if enabled."
  value       = var.enable_staging_slot && length(azurerm_linux_web_app_slot.this) > 0 ? azurerm_linux_web_app_slot.this[0].id : null
}

output "staging_slot_name" {
  description = "Name of the staging deployment slot, if enabled."
  value       = var.enable_staging_slot && length(azurerm_linux_web_app_slot.this) > 0 ? azurerm_linux_web_app_slot.this[0].name : null
}

output "staging_slot_default_hostname" {
  description = "Default hostname of the staging deployment slot, if enabled."
  value       = var.enable_staging_slot && length(azurerm_linux_web_app_slot.this) > 0 ? azurerm_linux_web_app_slot.this[0].default_hostname : null
}

output "log_analytics_workspace_id" {
  description = "Resource ID of the Log Analytics workspace."
  value       = local.log_analytics_workspace_id
}

output "application_insights_id" {
  description = "Resource ID of the Application Insights instance."
  value       = var.enable_application_insights && length(azurerm_application_insights.this) > 0 ? azurerm_application_insights.this[0].id : null
}

output "application_insights_connection_string" {
  description = "Connection string for Application Insights."
  value       = var.enable_application_insights && length(azurerm_application_insights.this) > 0 ? azurerm_application_insights.this[0].connection_string : null
  sensitive   = true
}

output "application_insights_instrumentation_key" {
  description = "Instrumentation key for Application Insights."
  value       = var.enable_application_insights && length(azurerm_application_insights.this) > 0 ? azurerm_application_insights.this[0].instrumentation_key : null
  sensitive   = true
}
