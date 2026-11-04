output "resource_group_name" {
  description = "Resource group containing the service."
  value       = local.resource_group_name
}

output "web_app_id" {
  description = "Resource ID of the Linux Web App."
  value       = azurerm_linux_web_app.this.id
}

output "web_app_name" {
  description = "Name of the Linux Web App."
  value       = azurerm_linux_web_app.this.name
}

output "default_hostname" {
  description = "Default *.azurewebsites.net hostname of the production slot."
  value       = azurerm_linux_web_app.this.default_hostname
}

output "url" {
  description = "HTTPS URL of the production slot."
  value       = "https://${azurerm_linux_web_app.this.default_hostname}"
}

output "principal_id" {
  description = "Object ID of the app's system-assigned managed identity (grant it Key Vault / storage / etc. access)."
  value       = azurerm_linux_web_app.this.identity[0].principal_id
}

output "outbound_ip_addresses" {
  description = "Possible outbound IPs of the app (for downstream allow-lists)."
  value       = split(",", azurerm_linux_web_app.this.possible_outbound_ip_addresses)
}

output "service_plan_id" {
  description = "Resource ID of the App Service Plan."
  value       = azurerm_service_plan.this.id
}

output "autoscale_setting_id" {
  description = "Resource ID of the autoscale setting (null on Basic SKUs)."
  value       = try(azurerm_monitor_autoscale_setting.this[0].id, null)
}

output "staging_slot_hostname" {
  description = "Hostname of the staging slot (null when the slot is disabled)."
  value       = try(azurerm_linux_web_app_slot.staging[0].default_hostname, null)
}

output "staging_slot_principal_id" {
  description = "Managed identity object ID of the staging slot (null when the slot is disabled)."
  value       = try(azurerm_linux_web_app_slot.staging[0].identity[0].principal_id, null)
}

output "log_analytics_workspace_id" {
  description = "Log Analytics workspace receiving logs, metrics and traces."
  value       = local.log_analytics_workspace_id
}

output "application_insights_id" {
  description = "Resource ID of the Application Insights component."
  value       = azurerm_application_insights.this.id
}

output "application_insights_connection_string" {
  description = "App Insights connection string (already injected into the app as APPLICATIONINSIGHTS_CONNECTION_STRING)."
  value       = azurerm_application_insights.this.connection_string
  sensitive   = true
}

output "action_group_id" {
  description = "Action group the standard alerts route to (null when alerts are disabled)."
  value       = local.action_group_id
}
