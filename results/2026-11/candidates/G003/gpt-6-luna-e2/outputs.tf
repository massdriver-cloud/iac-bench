output "app_name" {
  description = "Name of the production App Service."
  value       = azurerm_linux_web_app.service.name
}

output "app_url" {
  description = "HTTPS URL of the production App Service."
  value       = "https://${azurerm_linux_web_app.service.default_hostname}"
}

output "staging_slot_url" {
  description = "HTTPS URL for the pre-created staging deployment slot."
  value       = "https://${azurerm_linux_web_app_slot.staging.default_hostname}"
}

output "app_service_plan_id" {
  description = "ID of the Linux App Service plan."
  value       = azurerm_service_plan.service.id
}

output "app_identity_principal_id" {
  description = "System-assigned managed identity principal ID for the production app."
  value       = azurerm_linux_web_app.service.identity[0].principal_id
}

output "application_insights_connection_string" {
  description = "Connection string for instrumenting application telemetry."
  value       = azurerm_application_insights.service.connection_string
  sensitive   = true
}
