output "resource_group_name" {
  description = "Resource group everything for this service lives in."
  value       = azurerm_resource_group.this.name
}

output "app_name" {
  description = "Name of the production App Service web app."
  value       = azurerm_linux_web_app.this.name
}

output "app_id" {
  description = "Resource ID of the production App Service web app."
  value       = azurerm_linux_web_app.this.id
}

output "app_hostname" {
  description = "Default hostname of the production app."
  value       = azurerm_linux_web_app.this.default_hostname
}

output "app_url" {
  description = "HTTPS entry point of the service."
  value       = "https://${azurerm_linux_web_app.this.default_hostname}"
}

output "slot_hostnames" {
  description = "Default hostname per deployment slot, e.g. { staging = \"app-orders-staging.azurewebsites.net\" }."
  value       = { for slot_name, slot in azurerm_linux_web_app_slot.this : slot_name => slot.default_hostname }
}

output "service_plan_id" {
  description = "Resource ID of the App Service plan (capacity)."
  value       = azurerm_service_plan.this.id
}

output "managed_identity_principal_id" {
  description = "Object (principal) ID of the app's managed identity - grant it extra roles (Key Vault, storage, ...) with this."
  value       = azurerm_linux_web_app.this.identity[0].principal_id
}

output "application_insights_connection_string" {
  description = "Connection string for the service's Application Insights resource (sensitive)."
  value       = azurerm_application_insights.this.connection_string
  sensitive   = true
}

output "application_insights_app_id" {
  description = "App ID of the Application Insights resource (for dashboards and workbooks)."
  value       = azurerm_application_insights.this.app_id
}

output "log_analytics_workspace_id" {
  description = "Resource ID of the Log Analytics workspace receiving logs and metrics."
  value       = azurerm_log_analytics_workspace.this.id
}
