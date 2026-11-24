output "resource_group_name" {
  value = azurerm_resource_group.this.name
}
output "app_id" {
  value = azurerm_linux_web_app.this.id
}
output "app_name" {
  value = azurerm_linux_web_app.this.name
}
output "url" {
  value = "https://${azurerm_linux_web_app.this.default_hostname}"
}
output "staging_url" {
  value = var.staging_enabled ? "https://${azurerm_linux_web_app_slot.staging[0].default_hostname}" : null
}
output "principal_id" {
  value = azurerm_linux_web_app.this.identity[0].principal_id
}
output "staging_principal_id" {
  value = var.staging_enabled ? azurerm_linux_web_app_slot.staging[0].identity[0].principal_id : null
}
output "service_plan_id" {
  value = azurerm_service_plan.this.id
}
output "workspace_id" {
  value = azurerm_log_analytics_workspace.this.id
}
output "application_insights_connection_string" {
  value     = azurerm_application_insights.this.connection_string
  sensitive = true
}
output "action_group_id" {
  value = azurerm_monitor_action_group.this.id
}
