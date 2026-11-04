output "resource_group_name" {
  description = "Resource group containing the service."
  value       = local.rg_name
}

output "app_name" {
  description = "Web app name."
  value       = azurerm_linux_web_app.this.name
}

output "app_id" {
  description = "Web app resource id."
  value       = azurerm_linux_web_app.this.id
}

output "default_hostname" {
  description = "Default hostname of the web app."
  value       = azurerm_linux_web_app.this.default_hostname
}

output "url" {
  description = "HTTPS URL of the service."
  value       = "https://${azurerm_linux_web_app.this.default_hostname}"
}

output "staging_slot_hostname" {
  description = "Default hostname of the staging slot (null if disabled)."
  value       = try(azurerm_linux_web_app_slot.staging[0].default_hostname, null)
}

output "principal_id" {
  description = "Principal id of the app's system-assigned identity (grant e.g. AcrPull, Key Vault access)."
  value       = azurerm_linux_web_app.this.identity[0].principal_id
}

output "staging_slot_principal_id" {
  description = "Principal id of the staging slot's identity (null if disabled)."
  value       = try(azurerm_linux_web_app_slot.staging[0].identity[0].principal_id, null)
}

output "service_plan_id" {
  description = "App Service plan id."
  value       = azurerm_service_plan.this.id
}

output "application_insights_id" {
  description = "Application Insights resource id."
  value       = azurerm_application_insights.this.id
}

output "log_analytics_workspace_id" {
  description = "Log Analytics workspace id."
  value       = azurerm_log_analytics_workspace.this.id
}
