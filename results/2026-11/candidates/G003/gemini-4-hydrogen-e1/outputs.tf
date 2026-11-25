output "resource_group_name" {
  description = "Name of the Resource Group hosting the service."
  value       = local.resource_group_name
}

output "service_plan_id" {
  description = "Resource ID of the Linux App Service Plan."
  value       = azurerm_service_plan.this.id
}

output "web_app_id" {
  description = "Resource ID of the production Linux Web App."
  value       = azurerm_linux_web_app.this.id
}

output "web_app_name" {
  description = "Name of the production Linux Web App."
  value       = azurerm_linux_web_app.this.name
}

output "default_hostname" {
  description = "Default HTTPS hostname of the production Web App."
  value       = azurerm_linux_web_app.this.default_hostname
}

output "principal_id" {
  description = "System-assigned Managed Identity principal ID of the production Web App."
  value       = azurerm_linux_web_app.this.identity[0].principal_id
}

output "outbound_ip_addresses" {
  description = "Outbound IP addresses of the Web App."
  value       = azurerm_linux_web_app.this.outbound_ip_address_list
}

output "possible_outbound_ip_addresses" {
  description = "All possible outbound IP addresses across scaling events."
  value       = azurerm_linux_web_app.this.possible_outbound_ip_address_list
}

output "staging_slot_id" {
  description = "Resource ID of the staging deployment slot (null if disabled)."
  value       = local.effective_slots ? azurerm_linux_web_app_slot.staging[0].id : null
}

output "staging_slot_hostname" {
  description = "Default HTTPS hostname of the staging deployment slot (null if disabled)."
  value       = local.effective_slots ? azurerm_linux_web_app_slot.staging[0].default_hostname : null
}

output "staging_slot_principal_id" {
  description = "System-assigned Managed Identity principal ID of the staging slot (null if disabled)."
  value       = local.effective_slots ? azurerm_linux_web_app_slot.staging[0].identity[0].principal_id : null
}

output "log_analytics_workspace_id" {
  description = "Log Analytics Workspace ID receiving App Service logs and metrics."
  value       = local.log_analytics_workspace_id
}

output "application_insights_id" {
  description = "Resource ID of Application Insights (null if disabled)."
  value       = var.observability.app_insights_enabled ? azurerm_application_insights.this[0].id : null
}

output "application_insights_connection_string" {
  description = "Application Insights connection string (null if disabled)."
  value       = var.observability.app_insights_enabled ? azurerm_application_insights.this[0].connection_string : null
  sensitive   = true
}

output "autoscale_setting_id" {
  description = "Resource ID of the Azure Monitor autoscale setting (null if disabled)."
  value       = local.effective_autoscale ? azurerm_monitor_autoscale_setting.this[0].id : null
}
