output "resource_group_name" {
  description = "Name of the resource group the service lives in."
  value       = local.resource_group_name
}

output "service_plan_id" {
  description = "Resource ID of the service's dedicated App Service plan."
  value       = azurerm_service_plan.this.id
}

output "web_app_id" {
  description = "Resource ID of the web app."
  value       = azurerm_linux_web_app.this.id
}

output "web_app_name" {
  description = "Name of the web app."
  value       = azurerm_linux_web_app.this.name
}

output "web_app_default_hostname" {
  description = "Default hostname of the production app (https://<this>)."
  value       = azurerm_linux_web_app.this.default_hostname
}

output "web_app_identity_principal_id" {
  description = "Object ID of the app's system-assigned managed identity. Use it to grant the service access to databases, Key Vault, Service Bus, etc."
  value       = azurerm_linux_web_app.this.identity[0].principal_id
}

output "staging_slot_name" {
  description = "Name of the staging deployment slot (\"staging\"), or null when enable_staging_slot is false. Swap with: az webapp deployment slot swap -g <rg> -n <app> --slot staging --target-slot production"
  value       = var.enable_staging_slot ? azurerm_linux_web_app_slot.staging[0].name : null
}

output "staging_slot_default_hostname" {
  description = "Default hostname of the staging slot, or null when enable_staging_slot is false."
  value       = var.enable_staging_slot ? azurerm_linux_web_app_slot.staging[0].default_hostname : null
}

output "outbound_ip_addresses" {
  description = "Outbound IPs the service may call out from. Use for downstream firewall allow-lists."
  value       = azurerm_linux_web_app.this.outbound_ip_addresses
}

output "possible_outbound_ip_addresses" {
  description = "All IPs the service could call out from, including after a scale or SKU change."
  value       = azurerm_linux_web_app.this.possible_outbound_ip_addresses
}

output "application_insights_connection_string" {
  description = "Connection string for the service's Application Insights resource (already injected into the app's settings)."
  value       = azurerm_application_insights.this.connection_string
  sensitive   = true
}

output "log_analytics_workspace_id" {
  description = "Resource ID of the Log Analytics workspace receiving the service's logs and metrics."
  value       = local.log_analytics_workspace_id
}
