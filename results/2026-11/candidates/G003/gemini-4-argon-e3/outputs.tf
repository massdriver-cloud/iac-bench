output "resource_group_name" {
  description = "Name of the Resource Group hosting the service."
  value       = local.resource_group_name
}

output "service_plan_id" {
  description = "Resource ID of the App Service Plan."
  value       = azurerm_service_plan.this.id
}

output "web_app_id" {
  description = "Resource ID of the Linux Web App."
  value       = azurerm_linux_web_app.this.id
}

output "web_app_name" {
  description = "Name of the Linux Web App."
  value       = azurerm_linux_web_app.this.name
}

output "default_hostname" {
  description = "Default HTTPS hostname of the production Web App."
  value       = azurerm_linux_web_app.this.default_hostname
}

output "service_url" {
  description = "HTTPS endpoint URL of the production Web App."
  value       = "https://${azurerm_linux_web_app.this.default_hostname}"
}

output "staging_slot_id" {
  description = "Resource ID of the staging slot, if enabled."
  value       = try(azurerm_linux_web_app_slot.staging[0].id, null)
}

output "staging_hostname" {
  description = "Default HTTPS hostname of the staging slot, if enabled."
  value       = try(azurerm_linux_web_app_slot.staging[0].default_hostname, null)
}

output "system_assigned_identity_principal_id" {
  description = "Principal ID of the production app's system-assigned managed identity."
  value       = try(azurerm_linux_web_app.this.identity[0].principal_id, null)
}

output "staging_system_assigned_identity_principal_id" {
  description = "Principal ID of the staging slot's system-assigned managed identity."
  value       = try(azurerm_linux_web_app_slot.staging[0].identity[0].principal_id, null)
}

output "outbound_ip_addresses" {
  description = "Possible outbound IP addresses of the Web App."
  value       = azurerm_linux_web_app.this.possible_outbound_ip_address_list
}

output "log_analytics_workspace_id" {
  description = "Resource ID of the Log Analytics Workspace receiving diagnostics."
  value       = local.log_analytics_workspace_id
}

output "application_insights_id" {
  description = "Resource ID of the Application Insights instance, if enabled."
  value       = try(azurerm_application_insights.this[0].id, null)
}

output "application_insights_connection_string" {
  description = "Connection string for Application Insights."
  value       = try(azurerm_application_insights.this[0].connection_string, null)
  sensitive   = true
}
