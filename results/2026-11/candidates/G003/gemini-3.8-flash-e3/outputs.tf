###############################################################################
# Outputs: Service Identification & Access Endpoints
###############################################################################

output "service_name" {
  value       = var.service_name
  description = "The logical name of the deployed service."
}

output "environment" {
  value       = var.environment
  description = "The deployment environment."
}

output "app_service_id" {
  value       = azurerm_linux_web_app.app.id
  description = "The Azure Resource ID of the production Linux Web App."
}

output "app_service_name" {
  value       = azurerm_linux_web_app.app.name
  description = "The name of the production Linux Web App."
}

output "app_service_default_hostname" {
  value       = azurerm_linux_web_app.app.default_hostname
  description = "The default fully qualified domain name (FQDN) of the production Web App."
}

output "app_service_url" {
  value       = "https://${azurerm_linux_web_app.app.default_hostname}"
  description = "The HTTPS entrypoint URL for the production Web App."
}

###############################################################################
# Outputs: Rollout & Staging Slot
###############################################################################

output "staging_slot_enabled" {
  value       = var.enable_staging_slot
  description = "Whether a staging deployment slot was provisioned."
}

output "staging_slot_id" {
  value       = try(azurerm_linux_web_app_slot.staging[0].id, null)
  description = "The Azure Resource ID of the staging deployment slot."
}

output "staging_slot_name" {
  value       = try(azurerm_linux_web_app_slot.staging[0].name, null)
  description = "The name of the staging deployment slot."
}

output "staging_slot_default_hostname" {
  value       = try(azurerm_linux_web_app_slot.staging[0].default_hostname, null)
  description = "The default FQDN of the staging deployment slot."
}

output "staging_slot_url" {
  value       = var.enable_staging_slot ? "https://${azurerm_linux_web_app_slot.staging[0].default_hostname}" : null
  description = "The HTTPS entrypoint URL for the staging deployment slot."
}

###############################################################################
# Outputs: Capacity & Compute
###############################################################################

output "service_plan_id" {
  value       = local.service_plan_id
  description = "The Azure Resource ID of the hosting App Service Plan."
}

output "service_plan_name" {
  value       = local.service_plan_name
  description = "The name of the hosting App Service Plan."
}

output "autoscale_setting_id" {
  value       = try(azurerm_monitor_autoscale_setting.plan[0].id, null)
  description = "The Azure Resource ID of the autoscale configuration (if managed by this module)."
}

###############################################################################
# Outputs: Identity & Networking
###############################################################################

output "managed_identity_principal_id" {
  value       = try(azurerm_linux_web_app.app.identity[0].principal_id, null)
  description = "The Principal ID (Object ID) of the System-Assigned Managed Identity."
}

output "managed_identity_tenant_id" {
  value       = try(azurerm_linux_web_app.app.identity[0].tenant_id, null)
  description = "The Tenant ID of the System-Assigned Managed Identity."
}

output "outbound_ip_addresses" {
  value       = split(",", azurerm_linux_web_app.app.outbound_ip_addresses)
  description = "List of outbound IP addresses used by the Web App for external egress."
}

output "possible_outbound_ip_addresses" {
  value       = split(",", azurerm_linux_web_app.app.possible_outbound_ip_addresses)
  description = "List of all potential outbound IP addresses the Web App could use upon scaling."
}

###############################################################################
# Outputs: Health & Probes
###############################################################################

output "health_check_path" {
  value       = var.health_check_path
  description = "The configured health probe HTTP path."
}

output "health_check_url" {
  value       = "https://${azurerm_linux_web_app.app.default_hostname}${var.health_check_path}"
  description = "The complete health check probe URL for production."
}

###############################################################################
# Outputs: Observability & Telemetry
###############################################################################

output "log_analytics_workspace_id" {
  value       = local.log_analytics_workspace_id
  description = "The Resource ID of the Log Analytics workspace receiving service logs."
}

output "application_insights_id" {
  value       = try(azurerm_application_insights.appi[0].id, null)
  description = "The Azure Resource ID of the Application Insights component (if created)."
}

output "application_insights_app_id" {
  value       = local.app_insights_app_id
  description = "The Application ID of the Application Insights instance."
}

output "application_insights_connection_string" {
  value       = local.app_insights_connection_string
  sensitive   = true
  description = "The Application Insights Connection String configured for this service."
}

output "application_insights_instrumentation_key" {
  value       = local.app_insights_instrumentation_key
  sensitive   = true
  description = "The Application Insights Instrumentation Key configured for this service."
}
