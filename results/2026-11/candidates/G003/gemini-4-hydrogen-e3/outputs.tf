output "resource_group_name" {
  description = "Name of the Resource Group containing the service."
  value       = local.resource_group_name
}

output "service_plan_id" {
  description = "Resource ID of the App Service Plan."
  value       = local.create_service_plan ? azurerm_service_plan.this[0].id : var.capacity.existing_service_plan_id
}

output "service_plan_sku" {
  description = "Resolved App Service Plan SKU name."
  value       = local.sku_name
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
  description = "Default FQDN of the production web app."
  value       = azurerm_linux_web_app.this.default_hostname
}

output "url" {
  description = "HTTPS endpoint URL of the production web app."
  value       = "https://${azurerm_linux_web_app.this.default_hostname}"
}

output "staging_slot_id" {
  description = "Resource ID of the staging deployment slot, or null if slots are disabled."
  value       = local.enable_staging_slot ? azurerm_linux_web_app_slot.staging[0].id : null
}

output "staging_slot_hostname" {
  description = "Default FQDN of the staging deployment slot, or null if slots are disabled."
  value       = local.enable_staging_slot ? azurerm_linux_web_app_slot.staging[0].default_hostname : null
}

output "staging_slot_url" {
  description = "HTTPS endpoint URL of the staging deployment slot, or null if slots are disabled."
  value       = local.enable_staging_slot ? "https://${azurerm_linux_web_app_slot.staging[0].default_hostname}" : null
}

output "principal_id" {
  description = "System-assigned Managed Identity principal ID of the production web app."
  value       = azurerm_linux_web_app.this.identity[0].principal_id
}

output "staging_principal_id" {
  description = "System-assigned Managed Identity principal ID of the staging slot, or null if slots are disabled."
  value       = local.enable_staging_slot ? azurerm_linux_web_app_slot.staging[0].identity[0].principal_id : null
}

output "outbound_ip_addresses" {
  description = "Comma-separated list of outbound IP addresses used by the web app."
  value       = azurerm_linux_web_app.this.outbound_ip_addresses
}

output "possible_outbound_ip_addresses" {
  description = "Comma-separated list of all possible outbound IP addresses for firewall allow-listing."
  value       = azurerm_linux_web_app.this.possible_outbound_ip_addresses
}

output "log_analytics_workspace_id" {
  description = "Resource ID of the Log Analytics Workspace receiving logs and metrics."
  value       = local.log_analytics_workspace_id
}

output "application_insights_id" {
  description = "Resource ID of the Application Insights instance, or null if disabled."
  value       = local.create_app_insights ? azurerm_application_insights.this[0].id : null
}

output "application_insights_instrumentation_key" {
  description = "Application Insights instrumentation key, or null if disabled."
  value       = local.create_app_insights ? azurerm_application_insights.this[0].instrumentation_key : null
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "Application Insights connection string, or null if disabled."
  value       = local.create_app_insights ? azurerm_application_insights.this[0].connection_string : null
  sensitive   = true
}
