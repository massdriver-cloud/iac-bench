output "resource_group_name" {
  description = "Resource group containing all of the service's resources."
  value       = azurerm_resource_group.this.name
}

output "service_plan_id" {
  description = "ID of the App Service Plan (capacity) backing the service."
  value       = azurerm_service_plan.this.id
}

output "app_id" {
  description = "ID of the production web app."
  value       = azurerm_linux_web_app.this.id
}

output "app_name" {
  description = "Name of the production web app."
  value       = azurerm_linux_web_app.this.name
}

output "default_hostname" {
  description = "Public hostname of the production slot."
  value       = azurerm_linux_web_app.this.default_hostname
}

output "staging_hostname" {
  description = "Public hostname of the staging slot (null when the slot is disabled)."
  value       = try(azurerm_linux_web_app_slot.staging[0].default_hostname, null)
}

output "health_check_url" {
  description = "URL the platform health check and availability test use."
  value       = local.health_check_url
}

output "outbound_ip_addresses" {
  description = "All possible outbound IPs of the app; hand these to downstream services that need to allow-list the service."
  value       = azurerm_linux_web_app.this.outbound_ip_address_list
}

output "principal_id" {
  description = "Object ID of the app's system-assigned managed identity."
  value       = azurerm_linux_web_app.this.identity[0].principal_id
}

output "application_insights_connection_string" {
  description = "Connection string for the service's Application Insights resource."
  value       = azurerm_application_insights.this.connection_string
  sensitive   = true
}

output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics workspace receiving the service's logs and metrics."
  value       = azurerm_log_analytics_workspace.this.id
}
