output "resource_group_name" {
  description = "Resource group containing the service and its monitoring resources."
  value       = azurerm_resource_group.service.name
}

output "app_name" {
  description = "Production app name for Azure CLI and ARM operations."
  value       = azurerm_linux_web_app.service.name
}

output "app_id" {
  description = "Production App Service resource ID."
  value       = azurerm_linux_web_app.service.id
}

output "plan_id" {
  description = "App Service plan resource ID."
  value       = azurerm_service_plan.service.id
}

output "production_url" {
  description = "Production HTTPS URL on the Azure-provided hostname."
  value       = "https://${azurerm_linux_web_app.service.default_hostname}"
}

output "staging_slot_id" {
  description = "Staging slot resource ID, or null when disabled."
  value       = one(azurerm_linux_web_app_slot.staging[*].id)
}

output "staging_url" {
  description = "Staging HTTPS URL, subject to its ingress allowlist, or null when disabled."
  value       = var.enable_staging_slot ? "https://${azurerm_linux_web_app_slot.staging[0].default_hostname}" : null
}

output "runtime_principal_ids" {
  description = "System-assigned principal IDs by environment, for downstream access grants."
  value = merge(
    { production = azurerm_linux_web_app.service.identity[0].principal_id },
    var.enable_staging_slot ? { staging = azurerm_linux_web_app_slot.staging[0].identity[0].principal_id } : {}
  )
}

output "log_analytics_workspace_id" {
  description = "Log Analytics workspace resource ID for service diagnostics and application telemetry."
  value       = azurerm_log_analytics_workspace.service.id
}

output "application_insights_ids" {
  description = "Application Insights resource IDs by environment."
  value       = { for environment, component in azurerm_application_insights.app : environment => component.id }
}
