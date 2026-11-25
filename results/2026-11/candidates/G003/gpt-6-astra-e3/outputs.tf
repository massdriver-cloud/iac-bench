output "resource_group_name" {
  description = "Resource group owned by this module."
  value       = azurerm_resource_group.main.name
}

output "app_name" {
  description = "Production app name for deployment and swap commands."
  value       = azurerm_linux_web_app.main.name
}

output "app_id" {
  description = "Production app resource ID."
  value       = azurerm_linux_web_app.main.id
}

output "production_url" {
  description = "Public HTTPS production endpoint."
  value       = "https://${azurerm_linux_web_app.main.default_hostname}"
}

output "staging_url" {
  description = "Public HTTPS staging endpoint, or null when disabled."
  value       = var.staging_enabled ? "https://${azurerm_linux_web_app_slot.staging[0].default_hostname}" : null
}

output "managed_identity_principal_ids" {
  description = "Grant least-privilege access to dependencies (including Key Vault) to each slot separately."
  value = {
    production = azurerm_linux_web_app.main.identity[0].principal_id
    staging    = var.staging_enabled ? azurerm_linux_web_app_slot.staging[0].identity[0].principal_id : null
  }
}

output "service_plan_id" {
  description = "Plan resource ID for capacity operations."
  value       = local.service_plan_id
}

output "log_analytics_workspace_id" {
  description = "Workspace resource ID for diagnostics and queries."
  value       = azurerm_log_analytics_workspace.main.id
}

output "application_insights_connection_string" {
  description = "Connection string for application SDK instrumentation."
  value       = azurerm_application_insights.main.connection_string
  sensitive   = true
}

output "action_group_id" {
  description = "SRE alert routing action group ID."
  value       = azurerm_monitor_action_group.sre.id
}
