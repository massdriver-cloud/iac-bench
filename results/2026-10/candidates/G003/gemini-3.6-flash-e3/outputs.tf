output "resource_group_name" {
  value       = local.resource_group_name
  description = "Name of the resource group containing the App Service resources."
}

output "location" {
  value       = local.location
  description = "Azure region where resources are deployed."
}

output "service_plan_id" {
  value       = local.service_plan_id
  description = "ID of the App Service Plan."
}

output "web_app_id" {
  value       = azurerm_linux_web_app.this.id
  description = "ID of the primary Linux Web App."
}

output "web_app_name" {
  value       = azurerm_linux_web_app.this.name
  description = "Name of the primary Linux Web App."
}

output "web_app_default_hostname" {
  value       = azurerm_linux_web_app.this.default_hostname
  description = "Default hostname of the primary Linux Web App."
}

output "web_app_outbound_ip_addresses" {
  value       = azurerm_linux_web_app.this.outbound_ip_address_list
  description = "List of outbound IP addresses assigned to the Web App."
}

output "web_app_identity" {
  value       = azurerm_linux_web_app.this.identity
  description = "Managed Identity attributes for the Web App."
}

output "staging_slot_id" {
  value       = length(azurerm_linux_web_app_slot.staging) > 0 ? azurerm_linux_web_app_slot.staging[0].id : null
  description = "ID of the staging deployment slot (if enabled)."
}

output "staging_slot_default_hostname" {
  value       = length(azurerm_linux_web_app_slot.staging) > 0 ? azurerm_linux_web_app_slot.staging[0].default_hostname : null
  description = "Default hostname of the staging deployment slot (if enabled)."
}

output "application_insights_id" {
  value       = var.create_application_insights ? (length(azurerm_application_insights.this) > 0 ? azurerm_application_insights.this[0].id : null) : null
  description = "Resource ID of the created Application Insights instance."
}

output "application_insights_instrumentation_key" {
  value       = local.app_insights_instrumentation_key
  sensitive   = true
  description = "Instrumentation key for Application Insights."
}

output "application_insights_connection_string" {
  value       = local.app_insights_connection_string
  sensitive   = true
  description = "Connection string for Application Insights."
}
