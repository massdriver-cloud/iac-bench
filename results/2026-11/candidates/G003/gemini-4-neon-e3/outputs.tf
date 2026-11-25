output "resource_group_name" {
  description = "Name of the Resource Group hosting the App Service resources."
  value       = local.resource_group_name
}

output "service_plan_id" {
  description = "Resource ID of the Linux App Service Plan."
  value       = local.service_plan_id
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
  description = "Default azurewebsites.net hostname of the production Web App."
  value       = azurerm_linux_web_app.this.default_hostname
}

output "endpoint_url" {
  description = "HTTPS base URL of the production Web App."
  value       = "https://${azurerm_linux_web_app.this.default_hostname}"
}

output "custom_domain_verification_id" {
  description = "TXT record value (asuid.<domain>) required to verify custom domains."
  value       = azurerm_linux_web_app.this.custom_domain_verification_id
  sensitive   = true
}

output "principal_id" {
  description = "System-assigned Managed Identity principal ID of the production Web App."
  value       = azurerm_linux_web_app.this.identity[0].principal_id
}

output "outbound_ip_addresses" {
  description = "List of outbound IP addresses used by the production Web App."
  value       = azurerm_linux_web_app.this.outbound_ip_address_list
}

output "possible_outbound_ip_addresses" {
  description = "Full list of possible outbound IP addresses across scale units."
  value       = azurerm_linux_web_app.this.possible_outbound_ip_address_list
}

output "staging_slot_id" {
  description = "Resource ID of the staging deployment slot, or null if disabled."
  value       = var.rollout.staging_slot_enabled ? azurerm_linux_web_app_slot.staging[0].id : null
}

output "staging_slot_url" {
  description = "HTTPS base URL of the staging deployment slot, or null if disabled."
  value       = var.rollout.staging_slot_enabled ? "https://${azurerm_linux_web_app_slot.staging[0].default_hostname}" : null
}

output "staging_slot_principal_id" {
  description = "System-assigned Managed Identity principal ID of the staging deployment slot, or null if disabled."
  value       = var.rollout.staging_slot_enabled ? azurerm_linux_web_app_slot.staging[0].identity[0].principal_id : null
}

output "autoscale_setting_id" {
  description = "Resource ID of the Azure Monitor Autoscale setting, or null if disabled or using an external plan."
  value       = local.autoscale_enabled ? azurerm_monitor_autoscale_setting.this[0].id : null
}

output "log_analytics_workspace_id" {
  description = "Resource ID of the Log Analytics Workspace receiving logs and metrics, or null if observability is disabled."
  value       = local.log_analytics_workspace_id
}

output "application_insights_id" {
  description = "Resource ID of the Application Insights instance, or null if observability is disabled."
  value       = var.observability.enabled ? azurerm_application_insights.this[0].id : null
}

output "application_insights_connection_string" {
  description = "Connection string for Application Insights telemetry ingestion."
  value       = var.observability.enabled ? azurerm_application_insights.this[0].connection_string : null
  sensitive   = true
}

output "synthetic_web_test_id" {
  description = "Resource ID of the multi-region synthetic availability web test, or null if disabled."
  value       = local.synthetic_probe_enabled ? azurerm_application_insights_standard_web_test.this[0].id : null
}
