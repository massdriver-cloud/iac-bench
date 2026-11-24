output "resource_group_name" {
  description = "Resource group containing all service resources."
  value       = azurerm_resource_group.this.name
}

output "app_service_name" {
  description = "Name of the production App Service."
  value       = azurerm_linux_web_app.this.name
}

output "app_service_id" {
  description = "Resource ID of the production App Service."
  value       = azurerm_linux_web_app.this.id
}

output "default_hostname" {
  description = "Production hostname."
  value       = azurerm_linux_web_app.this.default_hostname
}

output "app_url" {
  description = "Production HTTPS URL."
  value       = "https://${azurerm_linux_web_app.this.default_hostname}"
}

output "staging_hostname" {
  description = "Staging slot hostname, or null when no slot exists."
  value       = local.staging_active ? azurerm_linux_web_app_slot.staging[0].default_hostname : null
}

output "principal_id" {
  description = "System-assigned managed identity principal ID of the production app (use for Key Vault / downstream RBAC)."
  value       = azurerm_linux_web_app.this.identity[0].principal_id
}

output "app_insights_connection_string" {
  description = "Application Insights connection string (null when disabled). Already injected into app settings."
  value       = var.enable_app_insights ? azurerm_application_insights.this[0].connection_string : null
  sensitive   = true
}

output "log_analytics_workspace_id" {
  description = "Log Analytics workspace receiving platform logs and metrics."
  value       = azurerm_log_analytics_workspace.this.id
}
