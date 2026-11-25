output "resource_group_name" {
  description = "Name of the resource group owned by this root module."
  value       = azurerm_resource_group.service.name
}

output "app_id" {
  description = "Production App Service resource ID."
  value       = azurerm_linux_web_app.service.id
}

output "app_url" {
  description = "Default production HTTPS URL."
  value       = "https://${azurerm_linux_web_app.service.default_hostname}"
}

output "app_principal_id" {
  description = "Production system-assigned identity principal ID for application permissions."
  value       = azurerm_linux_web_app.service.identity[0].principal_id
}

output "plan_id" {
  description = "App Service plan resource ID."
  value       = azurerm_service_plan.service.id
}

output "staging" {
  description = "Staging slot ID, HTTPS URL and system-assigned identity principal ID when enabled."
  value = one([
    for slot in azurerm_linux_web_app_slot.staging : {
      id           = slot.id
      url          = "https://${slot.default_hostname}"
      principal_id = slot.identity[0].principal_id
    }
  ])
}

output "workspace_id" {
  description = "Log Analytics workspace resource ID."
  value       = azurerm_log_analytics_workspace.service.id
}

output "application_insights_id" {
  description = "Application Insights resource ID."
  value       = azurerm_application_insights.service.id
}
