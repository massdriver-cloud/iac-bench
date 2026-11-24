output "resource_group_name" {
  description = "Resource group containing all of the service's resources."
  value       = azurerm_resource_group.this.name
}

output "web_app_name" {
  description = "Name of the production web app."
  value       = azurerm_linux_web_app.this.name
}

output "web_app_id" {
  description = "Resource ID of the production web app."
  value       = azurerm_linux_web_app.this.id
}

output "default_hostname" {
  description = "Production hostname (<name>.azurewebsites.net)."
  value       = azurerm_linux_web_app.this.default_hostname
}

output "url" {
  description = "Production HTTPS URL."
  value       = "https://${azurerm_linux_web_app.this.default_hostname}"
}

output "staging_hostname" {
  description = "Staging slot hostname, or null when the slot is disabled. Deploy here, warm up, then swap via your pipeline."
  value       = var.staging_slot_enabled ? azurerm_linux_web_app_slot.staging[0].default_hostname : null
}

output "staging_slot_id" {
  description = "Resource ID of the staging slot, or null when disabled."
  value       = var.staging_slot_enabled ? azurerm_linux_web_app_slot.staging[0].id : null
}

output "service_plan_id" {
  description = "Resource ID of the App Service plan (autoscale target)."
  value       = azurerm_service_plan.this.id
}

output "principal_id" {
  description = "System-assigned managed identity principal ID of the production app. Grant this identity access to ACR, Key Vault, databases, etc."
  value       = azurerm_linux_web_app.this.identity[0].principal_id
}

output "staging_principal_id" {
  description = "System-assigned managed identity principal ID of the staging slot (identities are slot-sticky and do not swap)."
  value       = var.staging_slot_enabled ? azurerm_linux_web_app_slot.staging[0].identity[0].principal_id : null
}

output "app_insights_connection_string" {
  description = "Application Insights connection string (also injected as APPLICATIONINSIGHTS_CONNECTION_STRING)."
  value       = azurerm_application_insights.this.connection_string
  sensitive   = true
}

output "log_analytics_workspace_id" {
  description = "Resource ID of the service's Log Analytics workspace."
  value       = azurerm_log_analytics_workspace.this.id
}

output "outbound_ip_addresses" {
  description = "Outbound IP addresses of the app (for allow-listing dependencies), when not using VNet integration."
  value       = azurerm_linux_web_app.this.outbound_ip_addresses
}
