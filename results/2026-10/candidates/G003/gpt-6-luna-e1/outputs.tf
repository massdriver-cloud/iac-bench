output "resource_group_name" {
  description = "Resource group containing this service."
  value       = azurerm_resource_group.app.name
}

output "web_app_name" {
  description = "Name of the production web app."
  value       = azurerm_linux_web_app.app.name
}

output "web_app_id" {
  description = "Azure resource ID of the production web app."
  value       = azurerm_linux_web_app.app.id
}

output "default_hostname" {
  description = "Default hostname of the production web app."
  value       = azurerm_linux_web_app.app.default_hostname
}

output "staging_hostname" {
  description = "Default hostname of the staging slot, or null when no slot is created."
  value       = var.create_staging_slot ? azurerm_linux_web_app_slot.staging[0].default_hostname : null
}

output "service_plan_id" {
  description = "Azure resource ID of the Linux App Service plan."
  value       = azurerm_service_plan.app.id
}

output "application_insights_connection_string" {
  description = "Application Insights connection string for instrumenting application code."
  value       = azurerm_application_insights.app.connection_string
  sensitive   = true
}

output "system_assigned_identity_principal_id" {
  description = "Principal ID of the production app's system-assigned managed identity."
  value       = azurerm_linux_web_app.app.identity[0].principal_id
}
