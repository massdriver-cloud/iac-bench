output "resource_group_name" {
  description = "Name of the Resource Group hosting the service."
  value       = local.rg_name
}

output "service_plan_id" {
  description = "Resource ID of the Linux App Service Plan."
  value       = azurerm_service_plan.this.id
}

output "service_plan_name" {
  description = "Name of the Linux App Service Plan."
  value       = azurerm_service_plan.this.name
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
  description = "Default hostname of the production Linux Web App."
  value       = azurerm_linux_web_app.this.default_hostname
}

output "https_endpoint" {
  description = "HTTPS base URL of the production web service."
  value       = "https://${azurerm_linux_web_app.this.default_hostname}"
}

output "health_check_url" {
  description = "Full HTTPS URL of the configured health check endpoint."
  value       = "https://${azurerm_linux_web_app.this.default_hostname}${var.health.path}"
}

output "principal_id" {
  description = "System-assigned Managed Identity principal (object) ID for the production app."
  value       = azurerm_linux_web_app.this.identity[0].principal_id
}

output "tenant_id" {
  description = "Tenant ID associated with the production app's System-assigned Managed Identity."
  value       = azurerm_linux_web_app.this.identity[0].tenant_id
}

output "outbound_ip_addresses" {
  description = "List of outbound IPv4 addresses used by the web app."
  value       = azurerm_linux_web_app.this.outbound_ip_address_list
}

output "possible_outbound_ip_addresses" {
  description = "List of all possible outbound IPv4 addresses across scale units."
  value       = azurerm_linux_web_app.this.possible_outbound_ip_address_list
}

output "staging_slot_id" {
  description = "Resource ID of the staging deployment slot (if enabled)."
  value       = try(azurerm_linux_web_app_slot.staging[0].id, null)
}

output "staging_slot_name" {
  description = "Name of the staging deployment slot (if enabled)."
  value       = try(azurerm_linux_web_app_slot.staging[0].name, null)
}

output "staging_slot_hostname" {
  description = "Default hostname of the staging deployment slot (if enabled)."
  value       = try(azurerm_linux_web_app_slot.staging[0].default_hostname, null)
}

output "staging_slot_principal_id" {
  description = "System-assigned Managed Identity principal ID for the staging slot (if enabled)."
  value       = try(azurerm_linux_web_app_slot.staging[0].identity[0].principal_id, null)
}

output "log_analytics_workspace_id" {
  description = "Resource ID of the Log Analytics Workspace receiving diagnostics and telemetry."
  value       = local.log_analytics_workspace_id
}

output "application_insights_id" {
  description = "Resource ID of the Application Insights component (if enabled)."
  value       = try(azurerm_application_insights.this[0].id, null)
}

output "application_insights_app_id" {
  description = "Application ID of the Application Insights instance (if enabled)."
  value       = try(azurerm_application_insights.this[0].app_id, null)
}

output "application_insights_connection_string" {
  description = "Connection string for Application Insights."
  value       = try(azurerm_application_insights.this[0].connection_string, null)
  sensitive   = true
}

output "zone_balancing_active" {
  description = "Whether availability zone balancing is active on the App Service Plan."
  value       = local.zone_balancing_enabled
}
