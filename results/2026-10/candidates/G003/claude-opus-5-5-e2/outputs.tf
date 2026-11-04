output "resource_group_name" {
  description = "Resource group containing the service."
  value       = local.resource_group_name
}

output "app_id" {
  description = "Web app resource ID."
  value       = azurerm_linux_web_app.this.id
}

output "app_name" {
  description = "Web app name."
  value       = azurerm_linux_web_app.this.name
}

output "url" {
  description = "Production URL."
  value       = "https://${azurerm_linux_web_app.this.default_hostname}"
}

output "staging_url" {
  description = "Staging slot URL (null when the slot is disabled)."
  value       = var.staging_slot_enabled ? "https://${azurerm_linux_web_app_slot.staging[0].default_hostname}" : null
}

output "service_plan_id" {
  description = "App Service plan ID."
  value       = azurerm_service_plan.this.id
}

output "identity_principal_id" {
  description = "Principal ID of the app's managed identity (grant it access to Key Vault, storage, etc.)."
  value       = azurerm_user_assigned_identity.this.principal_id
}

output "identity_client_id" {
  description = "Client ID of the app's managed identity."
  value       = azurerm_user_assigned_identity.this.client_id
}

output "outbound_ip_addresses" {
  description = "Possible outbound IPs of the app (for downstream allow-lists)."
  value       = azurerm_linux_web_app.this.possible_outbound_ip_address_list
}

output "application_insights_connection_string" {
  description = "Application Insights connection string."
  value       = azurerm_application_insights.this.connection_string
  sensitive   = true
}

output "log_analytics_workspace_id" {
  description = "Log Analytics workspace receiving logs and metrics."
  value       = local.workspace_id
}
