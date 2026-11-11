output "resource_group_name" {
  description = "Resource group the service was deployed into."
  value       = local.resource_group_name
}

output "app_service_id" {
  description = "Resource ID of the App Service web app."
  value       = azurerm_linux_web_app.this.id
}

output "app_service_name" {
  description = "Name of the App Service web app (its azurewebsites.net label)."
  value       = azurerm_linux_web_app.this.name
}

output "service_plan_id" {
  description = "Resource ID of the App Service plan."
  value       = azurerm_service_plan.this.id
}

output "service_uri" {
  description = "Public HTTPS endpoint of the service."
  value       = "https://${azurerm_linux_web_app.this.default_hostname}"
}

output "staging_slot_name" {
  description = "Name of the staging deployment slot, or null when disabled."
  value       = var.enable_staging_slot ? azurerm_linux_web_app_slot.staging[0].name : null
}

output "staging_uri" {
  description = "HTTPS endpoint of the staging deployment slot, or null when disabled."
  value       = var.enable_staging_slot ? "https://${azurerm_linux_web_app_slot.staging[0].default_hostname}" : null
}

output "principal_id" {
  description = "Object ID of the app's system-assigned managed identity (for Key Vault access and similar grants)."
  value       = azurerm_linux_web_app.this.identity[0].principal_id
}

output "autoscale_setting_id" {
  description = "Resource ID of the autoscale setting that manages instance count."
  value       = azurerm_monitor_autoscale_setting.this.id
}

output "log_analytics_workspace_id" {
  description = "Resource ID of the Log Analytics workspace receiving logs and metrics."
  value       = local.log_analytics_workspace_id
}

output "application_insights_connection_string" {
  description = "Application Insights connection string (also injected into the container as APPLICATIONINSIGHTS_CONNECTION_STRING)."
  value       = azurerm_application_insights.this.connection_string
  sensitive   = true
}

output "application_insights_instrumentation_key" {
  description = "Application Insights instrumentation key."
  value       = azurerm_application_insights.this.instrumentation_key
  sensitive   = true
}

output "action_group_id" {
  description = "Resource ID of the action group that pages on-call for this service."
  value       = azurerm_monitor_action_group.this.id
}
