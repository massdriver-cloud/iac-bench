output "resource_group_name" {
  description = "Dedicated resource group managed by this root."
  value       = azurerm_resource_group.this.name
}

output "app_id" {
  description = "Production App Service resource ID."
  value       = azurerm_linux_web_app.this.id
}

output "production_url" {
  description = "Public HTTPS production endpoint."
  value       = "https://${azurerm_linux_web_app.this.default_hostname}"
}

output "staging_url" {
  description = "Staging HTTPS endpoint, or null when disabled."
  value       = var.staging_enabled ? "https://${azurerm_linux_web_app_slot.staging[0].default_hostname}" : null
}

output "plan_id" {
  description = "Dedicated autoscaled service plan."
  value       = azurerm_service_plan.this.id
}

output "principal_ids" {
  description = "System identities for granting app-specific access to downstream resources."
  value = {
    production = azurerm_linux_web_app.this.identity[0].principal_id
    staging    = var.staging_enabled ? azurerm_linux_web_app_slot.staging[0].identity[0].principal_id : null
  }
}

output "log_analytics_workspace_id" {
  description = "Workspace resource ID for diagnostics and KQL."
  value       = azurerm_log_analytics_workspace.this.id
}

output "application_insights_connection_string" {
  description = "Configure the application SDK with this connection string (also injected into both containers)."
  value       = azurerm_application_insights.this.connection_string
  sensitive   = true
}

output "outbound_ip_addresses" {
  description = "Possible production outbound addresses. Use VNet integration plus NAT for fixed egress."
  value       = azurerm_linux_web_app.this.possible_outbound_ip_addresses
}
