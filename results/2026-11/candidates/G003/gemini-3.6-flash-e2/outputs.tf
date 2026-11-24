# -----------------------------------------------------------------------------
# Service Outputs
# -----------------------------------------------------------------------------

output "app_service_id" {
  description = "ID of the Linux Web App."
  value       = azurerm_linux_web_app.this.id
}

output "app_service_name" {
  description = "Name of the Linux Web App."
  value       = azurerm_linux_web_app.this.name
}

output "default_hostname" {
  description = "Default hostname (FQDN) of the Linux Web App."
  value       = azurerm_linux_web_app.this.default_hostname
}

output "service_plan_id" {
  description = "ID of the App Service Plan."
  value       = local.service_plan_id
}

# -----------------------------------------------------------------------------
# Identity Outputs
# -----------------------------------------------------------------------------

output "identity_principal_id" {
  description = "Principal ID of the Managed Identity assigned to the Linux Web App."
  value       = try(azurerm_linux_web_app.this.identity[0].principal_id, null)
}

output "identity_tenant_id" {
  description = "Tenant ID of the Managed Identity assigned to the Linux Web App."
  value       = try(azurerm_linux_web_app.this.identity[0].tenant_id, null)
}

# -----------------------------------------------------------------------------
# Observability Outputs
# -----------------------------------------------------------------------------

output "application_insights_id" {
  description = "ID of Application Insights resource."
  value       = try(azurerm_application_insights.this[0].id, null)
}

output "application_insights_instrumentation_key" {
  description = "Instrumentation key for Application Insights."
  value       = try(azurerm_application_insights.this[0].instrumentation_key, null)
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "Connection string for Application Insights."
  value       = try(azurerm_application_insights.this[0].connection_string, null)
  sensitive   = true
}

# -----------------------------------------------------------------------------
# Deployment Slot Outputs
# -----------------------------------------------------------------------------

output "staging_slot_id" {
  description = "ID of the staging deployment slot."
  value       = try(azurerm_linux_web_app_slot.staging[0].id, null)
}

output "staging_slot_hostname" {
  description = "Default hostname of the staging deployment slot."
  value       = try(azurerm_linux_web_app_slot.staging[0].default_hostname, null)
}
