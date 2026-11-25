output "resource_group_name" {
  description = "Name of the Azure Resource Group containing the service resources."
  value       = local.effective_resource_group_name
}

output "service_plan_id" {
  description = "Resource ID of the Linux App Service Plan hosting the service."
  value       = local.service_plan_id
}

output "web_app_id" {
  description = "Resource ID of the production Linux Web App."
  value       = azurerm_linux_web_app.this.id
}

output "web_app_name" {
  description = "Globally unique Azure name of the production Linux Web App."
  value       = azurerm_linux_web_app.this.name
}

output "default_hostname" {
  description = "Default *.azurewebsites.net hostname of the production Web App."
  value       = azurerm_linux_web_app.this.default_hostname
}

output "url" {
  description = "HTTPS endpoint URL of the production Web App."
  value       = "https://${azurerm_linux_web_app.this.default_hostname}"
}

output "staging_slot_id" {
  description = "Resource ID of the pre-production rollout slot, or null when staging_slot_enabled is false."
  value       = local.staging_slot_enabled ? azurerm_linux_web_app_slot.staging[0].id : null
}

output "staging_slot_name" {
  description = "Name of the pre-production rollout slot, or null when staging_slot_enabled is false."
  value       = local.staging_slot_enabled ? azurerm_linux_web_app_slot.staging[0].name : null
}

output "staging_slot_hostname" {
  description = "Default *.azurewebsites.net hostname of the pre-production rollout slot, or null when disabled."
  value       = local.staging_slot_enabled ? azurerm_linux_web_app_slot.staging[0].default_hostname : null
}

output "staging_slot_url" {
  description = "HTTPS endpoint URL of the pre-production rollout slot, or null when disabled."
  value       = local.staging_slot_enabled ? "https://${azurerm_linux_web_app_slot.staging[0].default_hostname}" : null
}

output "principal_id" {
  description = "Entra ID Principal (Object) ID of the production Web App System-Assigned Managed Identity."
  value       = azurerm_linux_web_app.this.identity[0].principal_id
}

output "staging_slot_principal_id" {
  description = "Entra ID Principal (Object) ID of the staging slot System-Assigned Managed Identity, or null when disabled."
  value       = local.staging_slot_enabled ? azurerm_linux_web_app_slot.staging[0].identity[0].principal_id : null
}

output "outbound_ip_address_list" {
  description = "List of active outbound IPv4 addresses used by the Web App when not routed through a VNet."
  value       = azurerm_linux_web_app.this.outbound_ip_address_list
}

output "possible_outbound_ip_address_list" {
  description = "Complete set of possible outbound IPv4 addresses across scale/SKU operations for egress allowlisting."
  value       = azurerm_linux_web_app.this.possible_outbound_ip_address_list
}

output "custom_domain_verification_id" {
  description = "Domain verification token (asuid TXT record value) for binding custom DNS hostnames."
  value       = azurerm_linux_web_app.this.custom_domain_verification_id
  sensitive   = true
}

output "log_analytics_workspace_id" {
  description = "Resource ID of the Log Analytics Workspace receiving logs and metrics, or null when observability is disabled."
  value       = local.log_analytics_id
}

output "application_insights_id" {
  description = "Resource ID of the Application Insights component, or null when disabled."
  value       = local.app_insights_enabled ? azurerm_application_insights.this[0].id : null
}

output "application_insights_app_id" {
  description = "Application ID of the Application Insights component (for API queries/dashboards), or null when disabled."
  value       = local.app_insights_enabled ? azurerm_application_insights.this[0].app_id : null
}

output "application_insights_connection_string" {
  description = "Connection string of the Application Insights component, or null when disabled."
  value       = local.app_insights_enabled ? azurerm_application_insights.this[0].connection_string : null
  sensitive   = true
}
