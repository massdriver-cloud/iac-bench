# =====================================================================================================================
# Service Identity & Resource Group Outputs
# =====================================================================================================================

output "service_name" {
  description = "The name of the service."
  value       = var.service_name
}

output "environment" {
  description = "The target deployment environment."
  value       = var.environment
}

output "resource_group_name" {
  description = "The resource group containing the App Service resources."
  value       = local.resource_group_name
}

# =====================================================================================================================
# Production App Service Outputs
# =====================================================================================================================

output "app_service_id" {
  description = "The resource ID of the production Linux Web App."
  value       = azurerm_linux_web_app.this.id
}

output "app_service_name" {
  description = "The name of the production Linux Web App."
  value       = azurerm_linux_web_app.this.name
}

output "default_hostname" {
  description = "The default public hostname of the production Web App."
  value       = azurerm_linux_web_app.this.default_hostname
}

output "default_url" {
  description = "The default HTTPS URL for the production Web App."
  value       = "https://${azurerm_linux_web_app.this.default_hostname}"
}

output "principal_id" {
  description = "The Principal ID of the production System-Assigned Managed Identity, used for granting Azure RBAC roles."
  value       = azurerm_linux_web_app.this.identity[0].principal_id
}

output "outbound_ip_addresses" {
  description = "List of outbound IP addresses used by the Web App for egress firewall allowlists."
  value       = split(",", azurerm_linux_web_app.this.outbound_ip_addresses)
}

output "possible_outbound_ip_addresses" {
  description = "List of all potential outbound IP addresses used by the Web App during scaling."
  value       = split(",", azurerm_linux_web_app.this.possible_outbound_ip_addresses)
}

# =====================================================================================================================
# Staging Deployment Slot Outputs
# =====================================================================================================================

output "staging_slot_id" {
  description = "The resource ID of the staging deployment slot, if enabled."
  value       = var.enable_staging_slot ? azurerm_linux_web_app_slot.staging[0].id : null
}

output "staging_slot_name" {
  description = "The name of the staging deployment slot, if enabled."
  value       = var.enable_staging_slot ? azurerm_linux_web_app_slot.staging[0].name : null
}

output "staging_default_hostname" {
  description = "The default hostname of the staging deployment slot, if enabled."
  value       = var.enable_staging_slot ? azurerm_linux_web_app_slot.staging[0].default_hostname : null
}

output "staging_default_url" {
  description = "The default HTTPS URL of the staging deployment slot, if enabled."
  value       = var.enable_staging_slot ? "https://${azurerm_linux_web_app_slot.staging[0].default_hostname}" : null
}

output "staging_principal_id" {
  description = "The Principal ID of the staging slot System-Assigned Managed Identity, if enabled."
  value       = var.enable_staging_slot ? azurerm_linux_web_app_slot.staging[0].identity[0].principal_id : null
}

# =====================================================================================================================
# Capacity & Infrastructure Outputs
# =====================================================================================================================

output "service_plan_id" {
  description = "The resource ID of the App Service Plan hosting the application."
  value       = local.service_plan_id
}

# =====================================================================================================================
# Observability Outputs
# =====================================================================================================================

output "log_analytics_workspace_id" {
  description = "The resource ID of the Log Analytics Workspace collecting telemetry and logs."
  value       = local.log_analytics_workspace_id
}

output "application_insights_id" {
  description = "The resource ID of the Application Insights component."
  value       = length(azurerm_application_insights.this) > 0 ? azurerm_application_insights.this[0].id : null
}

output "application_insights_connection_string" {
  description = "The connection string used for Application Insights telemetry ingestion."
  value       = local.application_insights_connection_string
  sensitive   = true
}
