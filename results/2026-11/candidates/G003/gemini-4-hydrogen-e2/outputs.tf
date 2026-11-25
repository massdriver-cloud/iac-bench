output "resource_group_name" {
  description = "Name of the resource group containing the service."
  value       = local.resource_group_name
}

output "service_plan_id" {
  description = "Resource ID of the App Service Plan."
  value       = local.service_plan_id
}

output "sku_name" {
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
  description = "Default hostname of the production Web App."
  value       = azurerm_linux_web_app.this.default_hostname
}

output "url" {
  description = "HTTPS URL of the production Web App."
  value       = "https://${azurerm_linux_web_app.this.default_hostname}"
}

output "principal_id" {
  description = "Principal ID of the production Web App's System Assigned Managed Identity."
  value       = azurerm_linux_web_app.this.identity[0].principal_id
}

output "outbound_ip_addresses" {
  description = "Comma-separated list of outbound IP addresses for the Web App."
  value       = azurerm_linux_web_app.this.outbound_ip_addresses
}

output "staging_slot_id" {
  description = "Resource ID of the staging deployment slot, if enabled."
  value       = local.staging_slot_enabled ? azurerm_linux_web_app_slot.staging[0].id : null
}

output "staging_slot_url" {
  description = "HTTPS URL of the staging deployment slot, if enabled."
  value       = local.staging_slot_enabled ? "https://${azurerm_linux_web_app_slot.staging[0].default_hostname}" : null
}

output "staging_slot_principal_id" {
  description = "Principal ID of the staging slot's System Assigned Managed Identity, if enabled."
  value       = local.staging_slot_enabled ? azurerm_linux_web_app_slot.staging[0].identity[0].principal_id : null
}

output "log_analytics_workspace_id" {
  description = "Resource ID of the Log Analytics Workspace used for diagnostics."
  value       = local.log_analytics_workspace_id
}

output "application_insights_id" {
  description = "Resource ID of the Application Insights resource, if created or provided."
  value       = var.observability.enabled ? (local.create_app_insights ? azurerm_application_insights.this[0].id : var.observability.application_insights_id) : null
}

output "application_insights_connection_string" {
  description = "Application Insights connection string injected into the app."
  value       = local.app_insights_connection_string
  sensitive   = true
}
