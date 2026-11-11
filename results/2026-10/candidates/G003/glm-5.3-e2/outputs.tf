output "app_service_name" {
  description = "Name of the production App Service app."
  value       = azurerm_linux_web_app.this.name
}

output "app_service_id" {
  description = "Resource id of the production App Service app."
  value       = azurerm_linux_web_app.this.id
}

output "resource_group_name" {
  description = "Resource group the service runs in."
  value       = local.resource_group_name
}

output "service_plan_id" {
  description = "Resource id of the App Service plan backing the service."
  value       = azurerm_service_plan.this.id
}

output "default_hostname" {
  description = "Public hostname of the production app."
  value       = azurerm_linux_web_app.this.default_hostname
}

output "app_uri" {
  description = "HTTPS endpoint of the production app."
  value       = "https://${azurerm_linux_web_app.this.default_hostname}"
}

output "slot_hostnames" {
  description = "Public hostname of each deployment slot, keyed by slot name."
  value       = { for name, slot in azurerm_linux_web_app_slot.this : name => slot.default_hostname }
}

output "outbound_ip_addresses" {
  description = "Outbound IP addresses currently used by the app, for allowlisting on dependencies."
  value       = azurerm_linux_web_app.this.outbound_ip_addresses
}

output "possible_outbound_ip_addresses" {
  description = "All possible outbound IP addresses (e.g. with autoscaling), for allowlisting on dependencies."
  value       = azurerm_linux_web_app.this.possible_outbound_ip_addresses
}

output "managed_identity_principal_id" {
  description = "Principal id of the app's system-assigned managed identity; grant it access to Key Vaults, databases, etc."
  value       = azurerm_linux_web_app.this.identity[0].principal_id
}

output "managed_identity_client_id" {
  description = "Client id of the app's system-assigned managed identity."
  value       = azurerm_linux_web_app.this.identity[0].client_id
}

output "application_insights_id" {
  description = "Resource id of the production App Insights component."
  value       = azurerm_application_insights.this.id
}

output "application_insights_connection_string" {
  description = "App Insights connection string for the production slot."
  sensitive   = true
  value       = azurerm_application_insights.this.connection_string
}

output "application_insights_instrumentation_key" {
  description = "App Insights instrumentation key for the production slot."
  sensitive   = true
  value       = azurerm_application_insights.this.instrumentation_key
}

output "log_analytics_workspace_id" {
  description = "Resource id of the Log Analytics workspace receiving the service's logs and metrics."
  value       = local.workspace_id
}
