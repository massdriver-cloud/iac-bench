output "service_url" {
  value = "https://${azurerm_linux_web_app.service.default_hostname}"
}
output "staging_url" {
  value = one([for slot in azurerm_linux_web_app_slot.staging : "https://${slot.default_hostname}"])
}
output "app_id" {
  value = azurerm_linux_web_app.service.id
}
output "plan_id" {
  value = azurerm_service_plan.service.id
}
output "resource_group_name" {
  value = azurerm_resource_group.service.name
}
output "workspace_id" {
  value = azurerm_log_analytics_workspace.service.workspace_id
}
output "app_principal_id" {
  value = azurerm_linux_web_app.service.identity[0].principal_id
}
