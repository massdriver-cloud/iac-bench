output "resource_group_name" {
  description = "Resource group containing the service."
  value       = local.resource_group_name
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
  description = "Production hostname."
  value       = azurerm_linux_web_app.this.default_hostname
}

output "staging_hostname" {
  description = "Staging slot hostname (null when the slot is disabled)."
  value       = var.enable_staging_slot ? azurerm_linux_web_app_slot.staging[0].default_hostname : null
}

output "service_plan_id" {
  description = "App Service plan ID."
  value       = azurerm_service_plan.this.id
}

output "principal_id" {
  description = "Object ID of the production app's managed identity (grant it Key Vault / data access)."
  value       = azurerm_linux_web_app.this.identity[0].principal_id
}

output "staging_principal_id" {
  description = "Object ID of the staging slot's managed identity."
  value       = var.enable_staging_slot ? azurerm_linux_web_app_slot.staging[0].identity[0].principal_id : null
}

output "application_insights_connection_string" {
  description = "Application Insights connection string."
  value       = azurerm_application_insights.this.connection_string
  sensitive   = true
}

output "log_analytics_workspace_id" {
  description = "Log Analytics workspace receiving diagnostics."
  value       = local.workspace_id
}

output "rollout_command" {
  description = "How to swap staging into production after verifying a new image on the staging slot."
  value       = var.enable_staging_slot ? "az webapp deployment slot swap -g ${local.resource_group_name} -n ${azurerm_linux_web_app.this.name} --slot staging --target-slot production" : null
}
