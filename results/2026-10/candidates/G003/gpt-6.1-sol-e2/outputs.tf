output "app_id" {
  description = "Production App Service resource ID."
  value       = azurerm_linux_web_app.this.id
}

output "production_url" {
  value = "https://${azurerm_linux_web_app.this.default_hostname}"
}

output "staging_url" {
  value = var.staging_enabled ? "https://${azurerm_linux_web_app_slot.staging[0].default_hostname}" : null
}

output "resource_group_name" {
  value = azurerm_resource_group.this.name
}

output "service_plan_id" {
  value = azurerm_service_plan.this.id
}

output "identity" {
  description = "Shared production/staging workload identity; grant external dependency permissions to principal_id."
  value = {
    id           = azurerm_user_assigned_identity.this.id
    client_id    = azurerm_user_assigned_identity.this.client_id
    principal_id = azurerm_user_assigned_identity.this.principal_id
  }
}

output "log_analytics_workspace_id" {
  value = azurerm_log_analytics_workspace.this.id
}

output "application_insights_id" {
  value = azurerm_application_insights.this.id
}

output "outbound_ip_addresses" {
  description = "All possible outbound addresses for dependency allowlists; not a fixed-egress guarantee."
  value       = azurerm_linux_web_app.this.possible_outbound_ip_address_list
}
