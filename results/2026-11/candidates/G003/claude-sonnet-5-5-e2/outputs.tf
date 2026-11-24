output "app_name" {
  description = "Web app name."
  value       = azurerm_linux_web_app.this.name
}

output "app_id" {
  description = "Web app resource ID."
  value       = azurerm_linux_web_app.this.id
}

output "default_hostname" {
  description = "Default hostname of the app."
  value       = azurerm_linux_web_app.this.default_hostname
}

output "staging_hostname" {
  description = "Default hostname of the staging slot, or null."
  value       = one(azurerm_linux_web_app_slot.staging[*].default_hostname)
}

output "principal_id" {
  description = "Managed identity principal ID of the app, for granting access to downstream resources."
  value       = azurerm_linux_web_app.this.identity[0].principal_id
}

output "service_plan_id" {
  description = "App Service plan ID."
  value       = azurerm_service_plan.this.id
}

output "resource_group_name" {
  description = "Resource group containing the resources."
  value       = local.rg_ref
}

output "application_insights_connection_string" {
  description = "Application Insights connection string."
  value       = azurerm_application_insights.this.connection_string
  sensitive   = true
}

output "log_analytics_workspace_id" {
  description = "Log Analytics workspace ID."
  value       = azurerm_log_analytics_workspace.this.id
}
