output "resource_group_name" {
  description = "Resource group containing the service."
  value       = local.resource_group_name
}

output "app_id" {
  description = "Resource ID of the web app."
  value       = azurerm_linux_web_app.this.id
}

output "app_name" {
  description = "Name of the web app."
  value       = azurerm_linux_web_app.this.name
}

output "url" {
  description = "Production URL."
  value       = "https://${azurerm_linux_web_app.this.default_hostname}"
}

output "staging_url" {
  description = "Staging slot URL (null when the slot is disabled)."
  value       = var.enable_staging_slot ? "https://${azurerm_linux_web_app_slot.staging[0].default_hostname}" : null
}

output "principal_id" {
  description = "Object ID of the production app's system-assigned identity (grant Key Vault / ACR / data access to this)."
  value       = azurerm_linux_web_app.this.identity[0].principal_id
}

output "staging_principal_id" {
  description = "Object ID of the staging slot's system-assigned identity."
  value       = var.enable_staging_slot ? azurerm_linux_web_app_slot.staging[0].identity[0].principal_id : null
}

output "service_plan_id" {
  description = "App Service plan ID."
  value       = azurerm_service_plan.this.id
}

output "outbound_ip_addresses" {
  description = "Possible outbound IPs (for allow-listing on downstream dependencies)."
  value       = azurerm_linux_web_app.this.possible_outbound_ip_address_list
}

output "application_insights_connection_string" {
  description = "App Insights connection string."
  value       = azurerm_application_insights.this.connection_string
  sensitive   = true
}

output "log_analytics_workspace_id" {
  description = "Workspace receiving app logs and metrics."
  value       = local.workspace_id
}

output "swap_command" {
  description = "Command to promote staging to production."
  value       = var.enable_staging_slot ? "az webapp deployment slot swap -g ${local.resource_group_name} -n ${azurerm_linux_web_app.this.name} --slot staging --target-slot production" : null
}
