output "app_service_name" {
  description = "Name of the App Service web app."
  value       = azurerm_linux_web_app.this.name
}

output "app_service_id" {
  description = "Resource ID of the App Service web app."
  value       = azurerm_linux_web_app.this.id
}

output "app_url" {
  description = "Public HTTPS endpoint of the service."
  value       = "https://${azurerm_linux_web_app.this.default_hostname}"
}

output "default_hostname" {
  description = "Default hostname of the service (<name>.azurewebsites.net)."
  value       = azurerm_linux_web_app.this.default_hostname
}

output "staging_slot_name" {
  description = "Name of the staging deployment slot, null when disabled."
  value       = one(azurerm_linux_web_app_slot.staging[*].name)
}

output "staging_url" {
  description = "HTTPS endpoint of the staging slot (null when disabled). Verify a candidate image here before promoting it."
  value       = local.staging_url
}

output "staging_hostname" {
  description = "Hostname of the staging slot (<name>-<slot>.azurewebsites.net), null when disabled."
  value       = local.staging_hostname
}

output "service_plan_id" {
  description = "Resource ID of the App Service plan."
  value       = azurerm_service_plan.this.id
}

output "resource_group_name" {
  description = "Resource group the service was deployed into."
  value       = local.resource_group_name
}

output "log_analytics_workspace_id" {
  description = "Resource ID of the service's Log Analytics workspace (platform, HTTP, console and capacity logs)."
  value       = azurerm_log_analytics_workspace.this.id
}

output "application_insights_id" {
  description = "Resource ID of the Application Insights resource."
  value       = azurerm_application_insights.this.id
}

output "application_insights_connection_string" {
  description = "Application Insights connection string; already injected into the container as APPLICATIONINSIGHTS_CONNECTION_STRING."
  value       = azurerm_application_insights.this.connection_string
  sensitive   = true
}

output "managed_identity_principal_id" {
  description = "Principal (object) ID of the app's system-assigned managed identity. Grant it access to backing services (databases, key vaults, queues)."
  value       = azurerm_linux_web_app.this.identity[0].principal_id
}

output "staging_managed_identity_principal_id" {
  description = "Principal (object) ID of the staging slot's managed identity, null when the slot is disabled."
  value       = one(azurerm_linux_web_app_slot.staging[*].identity[0].principal_id)
}
