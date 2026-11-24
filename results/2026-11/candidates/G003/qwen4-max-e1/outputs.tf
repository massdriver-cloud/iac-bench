output "resource_group_name" {
  description = "Resource group containing all service resources."
  value       = azurerm_resource_group.this.name
}

output "app_service_id" {
  description = "Resource ID of the production Linux Web App."
  value       = azurerm_linux_web_app.this.id
}

output "app_service_name" {
  description = "Name of the production Web App."
  value       = azurerm_linux_web_app.this.name
}

output "default_hostname" {
  description = "Default Azure hostname of the production app."
  value       = azurerm_linux_web_app.this.default_hostname
}

output "url" {
  description = "HTTPS URL of the production app."
  value       = "https://${azurerm_linux_web_app.this.default_hostname}"
}

output "staging_hostname" {
  description = "Default hostname of the staging slot (null when disabled)."
  value       = var.enable_staging_slot ? azurerm_linux_web_app_slot.staging[0].default_hostname : null
}

output "system_assigned_principal_id" {
  description = "Principal ID of the production app's system-assigned managed identity (grant it data-plane access, e.g. Key Vault, SQL, storage)."
  value       = azurerm_linux_web_app.this.identity[0].principal_id
}

output "staging_principal_id" {
  description = "Principal ID of the staging slot's managed identity (null when the slot is disabled)."
  value       = var.enable_staging_slot ? azurerm_linux_web_app_slot.staging[0].identity[0].principal_id : null
}

output "service_plan_id" {
  description = "Resource ID of the App Service Plan."
  value       = azurerm_service_plan.this.id
}

output "log_analytics_workspace_id" {
  description = "Workspace receiving platform logs, metrics and App Insights data."
  value       = local.workspace_id
}

output "app_insights_connection_string" {
  description = "Application Insights connection string (null when disabled)."
  value       = var.enable_app_insights ? azurerm_application_insights.this[0].connection_string : null
  sensitive   = true
}
