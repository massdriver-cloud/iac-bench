output "resource_group_name" {
  description = "Resource group the service was deployed into."
  value       = azurerm_resource_group.this.name
}

output "service_plan_id" {
  description = "Resource ID of the App Service plan."
  value       = azurerm_service_plan.this.id
}

output "web_app_id" {
  description = "Resource ID of the web app."
  value       = azurerm_linux_web_app.this.id
}

output "web_app_name" {
  description = "Name of the web app (includes the uniqueness suffix unless web_app_name was set explicitly)."
  value       = azurerm_linux_web_app.this.name
}

output "web_app_url" {
  description = "HTTPS URL of the production endpoint."
  value       = "https://${azurerm_linux_web_app.this.default_hostname}"
}

output "web_app_identity_principal_id" {
  description = "Object ID of the web app's system-assigned managed identity, for granting access to service-owned resources (Key Vault, Service Bus, SQL, ...)."
  value       = azurerm_linux_web_app.this.identity[0].principal_id
}

output "staging_slot_name" {
  description = "Name of the staging deployment slot, if one was created."
  value       = try(azurerm_linux_web_app_slot.staging[0].name, null)
}

output "staging_slot_url" {
  description = "HTTPS URL of the staging slot, if one was created."
  value       = try("https://${azurerm_linux_web_app_slot.staging[0].default_hostname}", null)
}

output "application_insights_connection_string" {
  description = "Connection string services use to ship telemetry to the module's Application Insights instance."
  value       = azurerm_application_insights.this.connection_string
  sensitive   = true
}

output "log_analytics_workspace_id" {
  description = "Resource ID of the Log Analytics workspace receiving logs and metrics."
  value       = azurerm_log_analytics_workspace.this.id
}
