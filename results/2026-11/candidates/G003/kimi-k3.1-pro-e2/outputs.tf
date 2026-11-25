output "web_app_id" {
  description = "Resource ID of the production Web App."
  value       = azurerm_linux_web_app.this.id
}

output "web_app_name" {
  description = "Name of the production Web App."
  value       = azurerm_linux_web_app.this.name
}

output "production_default_hostname" {
  description = "Default Azure hostname of the production Web App."
  value       = azurerm_linux_web_app.this.default_hostname
}

output "production_url" {
  description = "HTTPS URL of the production Web App."
  value       = "https://${azurerm_linux_web_app.this.default_hostname}"
}

output "production_identity_principal_id" {
  description = "System-assigned identity principal ID for production, useful for additional application-specific role assignments."
  value       = azurerm_linux_web_app.this.identity[0].principal_id
}

output "outbound_ip_addresses" {
  description = "Current production outbound IP addresses for downstream firewall configuration."
  value       = azurerm_linux_web_app.this.outbound_ip_address_list
}

output "possible_outbound_ip_addresses" {
  description = "All possible production outbound IP addresses, including addresses used after scaling or regional changes."
  value       = azurerm_linux_web_app.this.possible_outbound_ip_address_list
}

output "service_plan_id" {
  description = "Resource ID of the App Service plan."
  value       = local.service_plan_id
}

output "deployment_slot_id" {
  description = "Resource ID of the staging slot, or null when slots are disabled."
  value       = var.deployment_slot_enabled ? azurerm_linux_web_app_slot.staging[0].id : null
}

output "deployment_slot_name" {
  description = "Name of the deployment slot, or null when slots are disabled."
  value       = var.deployment_slot_enabled ? azurerm_linux_web_app_slot.staging[0].name : null
}

output "deployment_slot_default_hostname" {
  description = "Default hostname for candidate smoke tests, or null when slots are disabled."
  value       = var.deployment_slot_enabled ? azurerm_linux_web_app_slot.staging[0].default_hostname : null
}

output "deployment_slot_identity_principal_id" {
  description = "System-assigned identity principal ID of the staging slot, or null when slots are disabled."
  value       = var.deployment_slot_enabled ? azurerm_linux_web_app_slot.staging[0].identity[0].principal_id : null
}

output "application_insights_id" {
  description = "Resource ID of the workspace-backed Application Insights component."
  value       = azurerm_application_insights.this.id
}

output "application_insights_connection_string" {
  description = "Connection string for application SDKs. It is also supplied to both slots through APPLICATIONINSIGHTS_CONNECTION_STRING."
  value       = azurerm_application_insights.this.connection_string
  sensitive   = true
}

output "log_analytics_workspace_id" {
  description = "Resource ID of the Log Analytics workspace receiving logs, metrics and traces."
  value       = local.log_analytics_workspace_id
}

output "private_endpoint_ip_address" {
  description = "Private IP address of the production endpoint, or null when private ingress is disabled."
  value       = var.private_endpoint_subnet_id != null ? azurerm_private_endpoint.production[0].private_service_connection[0].private_ip_address : null
}

output "public_network_access_enabled" {
  description = "Effective public network access setting after applying the private-endpoint default."
  value       = local.public_network_access_enabled
}
