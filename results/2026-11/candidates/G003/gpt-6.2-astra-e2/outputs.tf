output "url" { value = "https://${azurerm_linux_web_app.service.default_hostname}" }
output "staging_url" { value = try("https://${azurerm_linux_web_app_slot.staging[0].default_hostname}", null) }
output "app_id" { value = azurerm_linux_web_app.service.id }
output "plan_id" { value = azurerm_service_plan.service.id }
output "workspace_id" { value = azurerm_log_analytics_workspace.service.id }
output "principal_id" { value = azurerm_linux_web_app.service.identity[0].principal_id }
