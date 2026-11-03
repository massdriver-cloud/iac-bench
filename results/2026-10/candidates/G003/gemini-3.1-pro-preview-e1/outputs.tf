output "default_hostname" {
  description = "The default hostname of the App Service."
  value       = azurerm_linux_web_app.this.default_hostname
}

output "staging_hostname" {
  description = "The default hostname of the staging slot, if enabled."
  value       = var.enable_staging_slot ? azurerm_linux_web_app_slot.staging[0].default_hostname : null
}

output "application_insights_instrumentation_key" {
  description = "The Instrumentation Key for the Application Insights instance."
  value       = azurerm_application_insights.this.instrumentation_key
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "The Connection String for the Application Insights instance."
  value       = azurerm_application_insights.this.connection_string
  sensitive   = true
}
