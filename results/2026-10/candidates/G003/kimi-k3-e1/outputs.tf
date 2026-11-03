output "resource_group_name" {
  description = "Resource group the service lives in."
  value       = azurerm_resource_group.main.name
}

output "app_service_plan_id" {
  description = "Resource id of the dedicated App Service Plan."
  value       = azurerm_service_plan.main.id
}

output "web_app_id" {
  description = "Resource id of the web app."
  value       = azurerm_linux_web_app.main.id
}

output "web_app_name" {
  description = "Name of the web app (target for CI deployments)."
  value       = azurerm_linux_web_app.main.name
}

output "default_hostname" {
  description = "Default hostname of the production slot."
  value       = azurerm_linux_web_app.main.default_hostname
}

output "url" {
  description = "HTTPS URL of the production slot."
  value       = "https://${azurerm_linux_web_app.main.default_hostname}"
}

output "health_probe_url" {
  description = "URL that health checks and the external availability test probe."
  value       = "https://${azurerm_linux_web_app.main.default_hostname}${local.health_probe_path}"
}

output "identity_principal_id" {
  description = "Object (principal) id of the system-assigned identity; use it to grant the service access to databases, Key Vault, Service Bus, etc."
  value       = azurerm_linux_web_app.main.identity[0].principal_id
}

output "staging_slot_name" {
  description = "Name of the deployment slot (deploy candidate builds here before promoting)."
  value       = local.slot_enabled ? local.slot_name : null
}

output "staging_slot_hostname" {
  description = "Hostname of the deployment slot."
  value       = local.slot_enabled ? azurerm_linux_web_app_slot.staging[0].default_hostname : null
}

output "application_insights_connection_string" {
  description = "Application Insights connection string (also injected into the app settings)."
  value       = var.application_insights_enabled ? azurerm_application_insights.main[0].connection_string : null
  sensitive   = true
}

output "log_analytics_workspace_id" {
  description = "Workspace receiving diagnostic logs/metrics (module-created or the one provided)."
  value       = local.log_analytics_workspace_id
}
