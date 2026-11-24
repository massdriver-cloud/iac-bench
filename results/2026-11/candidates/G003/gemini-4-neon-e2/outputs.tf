# ------------------------------------------------------------------------------
# Service & Placement Outputs
# ------------------------------------------------------------------------------

output "resource_group_name" {
  description = "Name of the Resource Group hosting the service."
  value       = local.rg_name
}

output "location" {
  description = "Azure region where the service is deployed."
  value       = local.rg_location
}

# ------------------------------------------------------------------------------
# Web App (Production) Outputs
# ------------------------------------------------------------------------------

output "web_app_id" {
  description = "Resource ID of the production Linux Web App."
  value       = azurerm_linux_web_app.this.id
}

output "web_app_name" {
  description = "Name of the production Linux Web App."
  value       = azurerm_linux_web_app.this.name
}

output "default_hostname" {
  description = "Default Azure hostname of the production Web App."
  value       = azurerm_linux_web_app.this.default_hostname
}

output "endpoint_url" {
  description = "HTTPS endpoint URL of the production Web App."
  value       = "https://${azurerm_linux_web_app.this.default_hostname}"
}

output "health_check_url" {
  description = "Full HTTPS health probe URL of the production Web App, or null if health checks are disabled."
  value       = var.health.path != null ? "https://${azurerm_linux_web_app.this.default_hostname}${var.health.path}" : null
}

output "principal_id" {
  description = "Principal ID of the production Web App's System-Assigned Managed Identity."
  value       = azurerm_linux_web_app.this.identity[0].principal_id
}

output "outbound_ip_addresses" {
  description = "Comma-separated outbound IP addresses of the production Web App."
  value       = azurerm_linux_web_app.this.outbound_ip_addresses
}

# ------------------------------------------------------------------------------
# Rollout (Staging Slot) Outputs
# ------------------------------------------------------------------------------

output "staging_slot_id" {
  description = "Resource ID of the staging deployment slot, or null if disabled."
  value       = try(azurerm_linux_web_app_slot.staging[0].id, null)
}

output "staging_slot_name" {
  description = "Name of the staging deployment slot, or null if disabled."
  value       = try(azurerm_linux_web_app_slot.staging[0].name, null)
}

output "staging_endpoint_url" {
  description = "HTTPS endpoint URL of the staging deployment slot, or null if disabled."
  value       = var.rollout.staging_slot_enabled ? "https://${azurerm_linux_web_app_slot.staging[0].default_hostname}" : null
}

output "staging_principal_id" {
  description = "Principal ID of the staging slot's System-Assigned Managed Identity, or null if disabled."
  value       = try(azurerm_linux_web_app_slot.staging[0].identity[0].principal_id, null)
}

# ------------------------------------------------------------------------------
# Capacity & Availability Outputs
# ------------------------------------------------------------------------------

output "service_plan_id" {
  description = "Resource ID of the Linux App Service Plan hosting the service."
  value       = local.service_plan_id
}

output "capacity_summary" {
  description = "Effective compute SKU, instance bounds, autoscaling, and zone redundancy configuration."
  value = {
    sku_name          = local.create_service_plan ? local.sku_name : "external"
    zone_redundant    = var.availability.zone_redundant
    autoscale_enabled = local.create_service_plan && var.capacity.autoscale_enabled
    min_instances     = local.effective_min_instances
    default_instances = local.effective_default_instances
    max_instances     = local.effective_max_instances
  }
}

# ------------------------------------------------------------------------------
# Observability Outputs
# ------------------------------------------------------------------------------

output "log_analytics_workspace_id" {
  description = "Resource ID of the Log Analytics Workspace receiving logs and metrics."
  value       = local.log_analytics_id
}

output "application_insights_id" {
  description = "Resource ID of the Application Insights component, or null if disabled."
  value       = try(azurerm_application_insights.this[0].id, null)
}

output "application_insights_connection_string" {
  description = "Application Insights connection string for SDK telemetry instrumentation."
  value       = try(azurerm_application_insights.this[0].connection_string, null)
  sensitive   = true
}

output "availability_test_id" {
  description = "Resource ID of the synthetic multi-region availability test, or null if disabled."
  value       = try(azurerm_application_insights_standard_web_test.this[0].id, null)
}

output "action_group_id" {
  description = "Resource ID of the module-managed Alert Action Group, if created."
  value       = try(azurerm_monitor_action_group.this[0].id, null)
}

# ------------------------------------------------------------------------------
# Networking Outputs
# ------------------------------------------------------------------------------

output "private_endpoint_id" {
  description = "Resource ID of the Private Endpoint, if enabled."
  value       = try(azurerm_private_endpoint.this[0].id, null)
}

output "private_endpoint_ip_address" {
  description = "Private IP address assigned to the Private Endpoint, if enabled."
  value       = try(azurerm_private_endpoint.this[0].private_service_connection[0].private_ip_address, null)
}
