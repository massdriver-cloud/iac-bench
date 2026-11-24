output "resource_group_name" {
  description = "Name of the owned resource group."
  value       = azurerm_resource_group.service.name
}

output "service_plan_id" {
  description = "Resource ID of the Linux App Service plan."
  value       = azurerm_service_plan.service.id
}

output "app_id" {
  description = "Production App Service resource ID."
  value       = azurerm_linux_web_app.production.id
}

output "app_url" {
  description = "HTTPS URL of the production app."
  value       = "https://${azurerm_linux_web_app.production.default_hostname}"
}

output "app_principal_id" {
  description = "Production system-assigned identity principal ID for runtime permissions."
  value       = azurerm_linux_web_app.production.identity[0].principal_id
}

output "staging_slot_id" {
  description = "Staging slot resource ID, or null if not created."
  value       = one(azurerm_linux_web_app_slot.staging[*].id)
}

output "staging_url" {
  description = "Staging HTTPS URL (subject to its allowlist), or null if there is no slot."
  value       = var.create_staging_slot ? "https://${azurerm_linux_web_app_slot.staging[0].default_hostname}" : null
}

output "staging_principal_id" {
  description = "Staging system-assigned identity principal ID, or null if there is no slot."
  value       = one([for slot in azurerm_linux_web_app_slot.staging : slot.identity[0].principal_id])
}

output "log_analytics_workspace_id" {
  description = "Resource ID of the workspace receiving application platform and container logs."
  value       = local.workspace_id
}
