output "resource_group_name" {
  description = "Name of the resource group hosting the App Service."
  value       = local.resource_group_name
}

output "service_plan_id" {
  description = "Resource ID of the App Service Plan."
  value       = azurerm_service_plan.this.id
}

output "service_plan_name" {
  description = "Name of the App Service Plan."
  value       = azurerm_service_plan.this.name
}

output "app_id" {
  description = "Resource ID of the production Linux Web App."
  value       = azurerm_linux_web_app.this.id
}

output "app_name" {
  description = "Name of the production Linux Web App."
  value       = azurerm_linux_web_app.this.name
}

output "default_hostname" {
  description = "Default HTTPS hostname of the production Linux Web App."
  value       = azurerm_linux_web_app.this.default_hostname
}

output "endpoint_url" {
  description = "HTTPS endpoint URL of the production service."
  value       = "https://${azurerm_linux_web_app.this.default_hostname}"
}

output "health_check_url" {
  description = "Full HTTPS URL to the configured health check endpoint."
  value       = "https://${azurerm_linux_web_app.this.default_hostname}${var.health.path}"
}

output "principal_id" {
  description = "System-assigned Managed Identity Principal ID of the production Web App."
  value       = azurerm_linux_web_app.this.identity[0].principal_id
}

output "outbound_ip_addresses" {
  description = "Possible outbound IP addresses of the Web App."
  value       = azurerm_linux_web_app.this.possible_outbound_ip_address_list
}

output "staging_slot_id" {
  description = "Resource ID of the staging deployment slot, if enabled."
  value       = try(azurerm_linux_web_app_slot.staging[0].id, null)
}

output "staging_slot_default_hostname" {
  description = "Default HTTPS hostname of the staging deployment slot, if enabled."
  value       = try(azurerm_linux_web_app_slot.staging[0].default_hostname, null)
}

output "staging_slot_principal_id" {
  description = "System-assigned Managed Identity Principal ID of the staging slot, if enabled."
  value       = try(azurerm_linux_web_app_slot.staging[0].identity[0].principal_id, null)
}

output "log_analytics_workspace_id" {
  description = "Resource ID of the Log Analytics Workspace receiving diagnostics."
  value       = local.log_analytics_workspace_id
}

output "application_insights_id" {
  description = "Resource ID of the Application Insights instance."
  value       = coalesce(var.observability.application_insights_id, try(azurerm_application_insights.this[0].id, null))
}

output "application_insights_app_id" {
  description = "Application ID of the created Application Insights component."
  value       = try(azurerm_application_insights.this[0].app_id, null)
}
