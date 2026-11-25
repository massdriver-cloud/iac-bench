# ==============================================================================
# Outputs
# ==============================================================================

output "resource_group_name" {
  description = "The name of the Resource Group in which the resources were deployed."
  value       = local.resource_group_name
}

output "location" {
  description = "The Azure region where resources were deployed."
  value       = local.location
}

output "app_service_plan_id" {
  description = "The ID of the App Service Plan."
  value       = local.service_plan_id
}

output "app_service_id" {
  description = "The ID of the Linux Web App."
  value       = azurerm_linux_web_app.app.id
}

output "app_service_name" {
  description = "The name of the Linux Web App."
  value       = azurerm_linux_web_app.app.name
}

output "default_hostname" {
  description = "The default hostname of the App Service."
  value       = azurerm_linux_web_app.app.default_hostname
}

output "app_service_url" {
  description = "The HTTPS URL of the primary App Service."
  value       = "https://${azurerm_linux_web_app.app.default_hostname}"
}

output "principal_id" {
  description = "The Principal ID of the System-Assigned Managed Identity for the primary App Service."
  value       = try(azurerm_linux_web_app.app.identity[0].principal_id, null)
}

output "staging_slot_id" {
  description = "The ID of the staging deployment slot."
  value       = var.enable_staging_slot ? azurerm_linux_web_app_slot.staging[0].id : null
}

output "staging_slot_name" {
  description = "The name of the staging deployment slot."
  value       = var.enable_staging_slot ? azurerm_linux_web_app_slot.staging[0].id : null
}

output "staging_slot_default_hostname" {
  description = "The default hostname of the staging deployment slot."
  value       = var.enable_staging_slot ? azurerm_linux_web_app_slot.staging[0].default_hostname : null
}

output "staging_slot_url" {
  description = "The HTTPS URL of the staging deployment slot."
  value       = var.enable_staging_slot ? "https://${azurerm_linux_web_app_slot.staging[0].default_hostname}" : null
}

output "log_analytics_workspace_id" {
  description = "The ID of the Log Analytics Workspace used for observability."
  value       = local.effective_log_analytics_workspace_id
}

output "application_insights_id" {
  description = "The ID of the Application Insights instance."
  value       = var.enable_observability && length(azurerm_application_insights.app) > 0 ? azurerm_application_insights.app[0].id : var.application_insights_id
}

output "application_insights_connection_string" {
  description = "The Connection String for Application Insights."
  value       = var.enable_observability && length(azurerm_application_insights.app) > 0 ? azurerm_application_insights.app[0].connection_string : null
  sensitive   = true
}

output "application_insights_instrumentation_key" {
  description = "The Instrumentation Key for Application Insights."
  value       = var.enable_observability && length(azurerm_application_insights.app) > 0 ? azurerm_application_insights.app[0].instrumentation_key : null
  sensitive   = true
}
