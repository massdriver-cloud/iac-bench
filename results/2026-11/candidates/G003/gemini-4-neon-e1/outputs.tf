output "resource_group_name" {
  description = "Resource group hosting the App Service resources."
  value       = local.resource_group_name
}

output "service_plan_id" {
  description = "Resource ID of the App Service Plan hosting the service."
  value       = local.service_plan_id
}

output "web_app_id" {
  description = "Resource ID of the production Linux Web App."
  value       = azurerm_linux_web_app.this.id
}

output "web_app_name" {
  description = "Name of the production Linux Web App."
  value       = azurerm_linux_web_app.this.name
}

output "production_hostname" {
  description = "Default HTTPS hostname of the production API."
  value       = azurerm_linux_web_app.this.default_hostname
}

output "production_url" {
  description = "Base HTTPS URL of the production API."
  value       = "https://${azurerm_linux_web_app.this.default_hostname}"
}

output "production_principal_id" {
  description = "System-assigned managed identity principal ID of the production app (use for ACR Pull / Key Vault RBAC)."
  value       = azurerm_linux_web_app.this.identity[0].principal_id
}

output "staging_slot_id" {
  description = "Resource ID of the staging deployment slot, or null if staging slot is disabled."
  value       = var.rollouts.enable_staging_slot ? azurerm_linux_web_app_slot.staging[0].id : null
}

output "staging_hostname" {
  description = "Default HTTPS hostname of the staging slot for pre-swap smoke tests, or null if disabled."
  value       = var.rollouts.enable_staging_slot ? azurerm_linux_web_app_slot.staging[0].default_hostname : null
}

output "staging_url" {
  description = "Base HTTPS URL of the staging slot, or null if disabled."
  value       = var.rollouts.enable_staging_slot ? "https://${azurerm_linux_web_app_slot.staging[0].default_hostname}" : null
}

output "staging_principal_id" {
  description = "System-assigned managed identity principal ID of the staging slot (grant matching ACR/Key Vault RBAC), or null if disabled."
  value       = var.rollouts.enable_staging_slot ? azurerm_linux_web_app_slot.staging[0].identity[0].principal_id : null
}

output "outbound_ip_addresses" {
  description = "List of outbound IP addresses used by the production app (useful for downstream allowlists)."
  value       = azurerm_linux_web_app.this.outbound_ip_address_list
}

output "possible_outbound_ip_addresses" {
  description = "Full list of possible outbound IP addresses across plan scaling events."
  value       = azurerm_linux_web_app.this.possible_outbound_ip_address_list
}

output "log_analytics_workspace_id" {
  description = "Resource ID of the Log Analytics workspace receiving diagnostics and Application Insights telemetry."
  value       = local.log_analytics_workspace_id
}

output "application_insights_id" {
  description = "Resource ID of Application Insights, or null if disabled."
  value       = var.observability.enable_application_insights ? azurerm_application_insights.this[0].id : null
}

output "application_insights_connection_string" {
  description = "Application Insights connection string (automatically injected into the container as APPLICATIONINSIGHTS_CONNECTION_STRING)."
  value       = var.observability.enable_application_insights ? azurerm_application_insights.this[0].connection_string : null
  sensitive   = true
}

output "resolved_capacity" {
  description = "Effective compute SKU, zone redundancy, and scaling bounds resolved from the SRE capacity and availability inputs."
  value = {
    sku_name         = local.create_service_plan ? local.sku_name : "external-plan"
    zone_redundant   = local.create_service_plan ? local.zone_redundant : null
    min_instances    = local.create_service_plan ? local.min_instances : null
    max_instances    = local.create_service_plan ? local.max_instances : null
    scale_step       = local.create_service_plan ? local.scale_step : null
    autoscale_active = local.autoscale_active
  }
}
