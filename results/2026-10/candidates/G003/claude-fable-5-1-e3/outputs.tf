output "resource_group_name" {
  description = "Resource group containing the service."
  value       = local.resource_group_name
}

output "web_app_id" {
  description = "Resource ID of the production Web App."
  value       = azurerm_linux_web_app.this.id
}

output "web_app_name" {
  description = "Name of the production Web App."
  value       = azurerm_linux_web_app.this.name
}

output "url" {
  description = "HTTPS URL of the production app."
  value       = "https://${azurerm_linux_web_app.this.default_hostname}"
}

output "default_hostname" {
  description = "Default hostname of the production app."
  value       = azurerm_linux_web_app.this.default_hostname
}

output "staging_url" {
  description = "HTTPS URL of the staging slot (null when the slot is disabled)."
  value       = var.staging_slot_enabled ? "https://${azurerm_linux_web_app_slot.staging[0].default_hostname}" : null
}

output "service_plan_id" {
  description = "Resource ID of the App Service Plan."
  value       = azurerm_service_plan.this.id
}

output "identity_principal_id" {
  description = "Principal ID of the managed identity used by the app and slot. Grant it access to Key Vault, storage, etc."
  value       = azurerm_user_assigned_identity.this.principal_id
}

output "identity_client_id" {
  description = "Client ID of the managed identity (for AZURE_CLIENT_ID in workload code)."
  value       = azurerm_user_assigned_identity.this.client_id
}

output "outbound_ip_addresses" {
  description = "Possible outbound IP addresses of the app, for firewall allow-lists."
  value       = split(",", azurerm_linux_web_app.this.possible_outbound_ip_addresses)
}

output "log_analytics_workspace_id" {
  description = "Log Analytics workspace receiving logs and telemetry."
  value       = local.log_analytics_workspace_id
}

output "application_insights_id" {
  description = "Resource ID of the Application Insights component."
  value       = azurerm_application_insights.this.id
}

output "application_insights_connection_string" {
  description = "Application Insights connection string."
  value       = azurerm_application_insights.this.connection_string
  sensitive   = true
}
