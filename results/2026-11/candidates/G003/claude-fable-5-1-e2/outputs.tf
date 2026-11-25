output "resource_group_name" {
  description = "Resource group holding every resource for this service."
  value       = azurerm_resource_group.this.name
}

output "app_service_id" {
  description = "Resource ID of the production web app."
  value       = azurerm_linux_web_app.this.id
}

output "app_service_name" {
  description = "Name of the production web app (use with `az webapp ...`)."
  value       = azurerm_linux_web_app.this.name
}

output "default_hostname" {
  description = "Public hostname of the production app."
  value       = azurerm_linux_web_app.this.default_hostname
}

output "url" {
  description = "HTTPS URL of the production app."
  value       = "https://${azurerm_linux_web_app.this.default_hostname}"
}

output "staging_slot_name" {
  description = "Name of the staging slot (null when disabled). Deploy here, verify, then `az webapp deployment slot swap`."
  value       = local.staging_slot ? azurerm_linux_web_app_slot.staging[0].name : null
}

output "staging_hostname" {
  description = "Hostname of the staging slot (null when disabled)."
  value       = local.staging_slot ? azurerm_linux_web_app_slot.staging[0].default_hostname : null
}

output "service_plan_id" {
  description = "Resource ID of the App Service plan."
  value       = azurerm_service_plan.this.id
}

output "identity_principal_id" {
  description = "Principal ID of the system-assigned identity of the production app (grant this access to downstream resources)."
  value       = azurerm_linux_web_app.this.identity[0].principal_id
}

output "user_assigned_identity_id" {
  description = "Resource ID of the user-assigned identity shared by the app and its slot (used for ACR pull)."
  value       = azurerm_user_assigned_identity.this.id
}

output "outbound_ip_addresses" {
  description = "Outbound IPs of the app, for allow-listing on downstream systems."
  value       = azurerm_linux_web_app.this.possible_outbound_ip_address_list
}

output "log_analytics_workspace_id" {
  description = "Resource ID of the Log Analytics workspace that receives app logs and metrics."
  value       = azurerm_log_analytics_workspace.this.id
}

output "application_insights_connection_string" {
  description = "App Insights connection string (already injected into the app)."
  value       = azurerm_application_insights.this.connection_string
  sensitive   = true
}

output "action_group_id" {
  description = "Action group that receives the standard alerts; attach additional alert rules to it."
  value       = azurerm_monitor_action_group.this.id
}
