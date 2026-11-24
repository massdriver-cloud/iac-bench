# ---------------------------------------------------------------------------
# Outputs the SREs actually consume.
# ---------------------------------------------------------------------------

output "id" {
  description = "Resource id of the production Linux Web App."
  value       = azurerm_linux_web_app.this.id
}

output "name" {
  description = "Name of the production Linux Web App."
  value       = azurerm_linux_web_app.this.name
}

output "default_hostname" {
  description = "Default hostname (https://<name>.azurewebsites.net)."
  value       = azurerm_linux_web_app.this.default_hostname
}

output "identity_principal_id" {
  description = "Principal id of the system-assigned managed identity."
  value       = azurerm_linux_web_app.this.identity[0].principal_id
}

output "staging_slot_id" {
  description = "Resource id of the staging slot, when slot_enabled."
  value       = var.slot_enabled ? azurerm_linux_web_app_slot.staging[0].id : null
}

output "staging_default_hostname" {
  description = "Default hostname of the staging slot."
  value       = var.slot_enabled ? azurerm_linux_web_app_slot.staging[0].default_hostname : null
}

output "outbound_ip_addresses" {
  description = "Outbound IP addresses of the plan."
  value       = azurerm_linux_web_app.this.outbound_ip_address_list
}

output "app_insights_connection_string" {
  description = "Connection string of the provisioned Application Insights instance."
  value       = var.app_insights_enabled ? azurerm_application_insights.this[0].connection_string : null
  sensitive   = true
}

output "app_insights_instrumentation_key" {
  description = "Instrumentation key of the provisioned Application Insights instance."
  value       = var.app_insights_enabled ? azurerm_application_insights.this[0].instrumentation_key : null
  sensitive   = true
}