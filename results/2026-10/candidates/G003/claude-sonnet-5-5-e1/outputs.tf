output "app_id" {
  description = "Resource ID of the web app."
  value       = azurerm_linux_web_app.this.id
}

output "default_hostname" {
  description = "Default hostname of the production app."
  value       = azurerm_linux_web_app.this.default_hostname
}

output "url" {
  description = "HTTPS URL of the production app."
  value       = "https://${azurerm_linux_web_app.this.default_hostname}"
}

output "staging_slot_hostname" {
  description = "Hostname of the staging slot (null if disabled)."
  value       = var.enable_staging_slot ? azurerm_linux_web_app_slot.staging[0].default_hostname : null
}

output "principal_id" {
  description = "Managed identity principal ID of the production app, for granting access to Key Vault, databases, etc."
  value       = azurerm_linux_web_app.this.identity[0].principal_id
}

output "staging_slot_principal_id" {
  description = "Managed identity principal ID of the staging slot (null if disabled)."
  value       = var.enable_staging_slot ? azurerm_linux_web_app_slot.staging[0].identity[0].principal_id : null
}

output "service_plan_id" {
  description = "Resource ID of the App Service plan."
  value       = azurerm_service_plan.this.id
}

output "application_insights_id" {
  description = "Resource ID of Application Insights."
  value       = azurerm_application_insights.this.id
}

output "log_analytics_workspace_id" {
  description = "Log Analytics workspace receiving diagnostics."
  value       = local.workspace_id
}
