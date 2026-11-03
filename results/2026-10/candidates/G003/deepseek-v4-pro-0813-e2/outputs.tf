output "app_service_id" {
  description = "Resource ID of the production App Service."
  value       = azurerm_linux_web_app.this.id
}

output "app_service_url" {
  description = "Default hostname of the production app."
  value       = "https://${azurerm_linux_web_app.this.default_hostname}"
}

output "app_service_name" {
  description = "Name of the production App Service."
  value       = azurerm_linux_web_app.this.name
}

output "system_identity_principal_id" {
  description = "Principal ID of the system-assigned managed identity (null when disabled)."
  value       = var.system_identity_enabled ? azurerm_linux_web_app.this.identity[0].principal_id : null
}

output "service_plan_id" {
  description = "Resource ID of the App Service Plan the app runs on."
  value       = local.plan_id
}

output "staging_slot_id" {
  description = "Resource ID of the staging slot (null when disabled)."
  value       = var.slot_enabled ? azurerm_linux_web_app_slot.staging[0].id : null
}

output "staging_slot_url" {
  description = "Default hostname of the staging slot (null when disabled)."
  value       = var.slot_enabled ? "https://${azurerm_linux_web_app_slot.staging[0].default_hostname}" : null
}

output "traffic_routing" {
  description = "Intended production/staging traffic split (only meaningful when slot_enabled)."
  value = var.slot_enabled ? {
    production = 100 - var.staging_traffic
    staging    = var.staging_traffic
  } : null
}

output "application_insights_connection_string" {
  description = "Connection string for Application Insights (null when disabled)."
  value       = var.app_insights_enabled ? azurerm_application_insights.this[0].connection_string : null
  sensitive   = true
}

output "application_insights_instrumentation_key" {
  description = "Instrumentation key for Application Insights (null when disabled)."
  value       = var.app_insights_enabled ? azurerm_application_insights.this[0].instrumentation_key : null
  sensitive   = true
}