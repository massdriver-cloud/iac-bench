# -----------------------------------------------------------------------------
# Core Service Endpoints & Identifiers
# -----------------------------------------------------------------------------

output "resource_group_name" {
  description = "Name of the Resource Group hosting the service."
  value       = local.create_resource_group ? azurerm_resource_group.this[0].name : local.resource_group_name
}

output "service_plan_id" {
  description = "Resource ID of the Linux App Service Plan running the service."
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

output "default_hostname" {
  description = "Default Azure hostname of the production Web App."
  value       = azurerm_linux_web_app.this.default_hostname
}

output "service_url" {
  description = "HTTPS base URL of the production service."
  value       = "https://${azurerm_linux_web_app.this.default_hostname}"
}

output "health_check_url" {
  description = "Full HTTPS health probe URL of the production service."
  value       = "https://${azurerm_linux_web_app.this.default_hostname}${var.health.path}"
}

# -----------------------------------------------------------------------------
# Rollout & Staging Slot Outputs
# -----------------------------------------------------------------------------

output "staging_slot_id" {
  description = "Resource ID of the pre-production staging deployment slot, or null when disabled."
  value       = var.rollout.staging_slot_enabled ? azurerm_linux_web_app_slot.staging[0].id : null
}

output "staging_slot_name" {
  description = "Name of the staging deployment slot, or null when disabled."
  value       = var.rollout.staging_slot_enabled ? azurerm_linux_web_app_slot.staging[0].name : null
}

output "staging_slot_hostname" {
  description = "Default hostname of the staging deployment slot, or null when disabled."
  value       = var.rollout.staging_slot_enabled ? azurerm_linux_web_app_slot.staging[0].default_hostname : null
}

output "staging_slot_url" {
  description = "HTTPS base URL of the staging deployment slot, or null when disabled."
  value       = var.rollout.staging_slot_enabled ? "https://${azurerm_linux_web_app_slot.staging[0].default_hostname}" : null
}

# -----------------------------------------------------------------------------
# Identity & Network Egress / Private Ingress
# -----------------------------------------------------------------------------

output "principal_id" {
  description = "Principal (Object) ID of the production Web App's System-Assigned Managed Identity."
  value       = azurerm_linux_web_app.this.identity[0].principal_id
}

output "tenant_id" {
  description = "Microsoft Entra Tenant ID of the production Web App's System-Assigned Managed Identity."
  value       = azurerm_linux_web_app.this.identity[0].tenant_id
}

output "staging_slot_principal_id" {
  description = "Principal (Object) ID of the staging slot's System-Assigned Managed Identity, or null when disabled."
  value       = var.rollout.staging_slot_enabled ? azurerm_linux_web_app_slot.staging[0].identity[0].principal_id : null
}

output "outbound_ip_addresses" {
  description = "Active outbound IPv4 addresses used by the Web App when VNet egress routing is not enabled."
  value       = azurerm_linux_web_app.this.outbound_ip_address_list
}

output "possible_outbound_ip_addresses" {
  description = "Superset of possible outbound IPv4 addresses across scale operations for downstream firewall allowlisting."
  value       = azurerm_linux_web_app.this.possible_outbound_ip_address_list
}

output "custom_domain_verification_id" {
  description = "Domain verification token (asuid TXT record value) for binding custom DNS hostnames to the Web App."
  value       = azurerm_linux_web_app.this.custom_domain_verification_id
  sensitive   = true
}

output "private_endpoint_id" {
  description = "Resource ID of the Private Endpoint when private ingress is enabled, or null otherwise."
  value       = var.network.private_endpoint != null ? azurerm_private_endpoint.this[0].id : null
}

output "private_endpoint_ip_address" {
  description = "Private IPv4 address allocated to the Web App Private Endpoint, or null when not configured."
  value       = var.network.private_endpoint != null ? azurerm_private_endpoint.this[0].private_service_connection[0].private_ip_address : null
}

# -----------------------------------------------------------------------------
# Observability Outputs
# -----------------------------------------------------------------------------

output "log_analytics_workspace_id" {
  description = "Resource ID of the Log Analytics Workspace receiving logs and metrics for this service."
  value       = local.log_analytics_workspace_id
}

output "application_insights_id" {
  description = "Resource ID of the module-managed Application Insights component, or null when disabled or externally supplied."
  value       = local.create_app_insights ? azurerm_application_insights.this[0].id : null
}

output "application_insights_app_id" {
  description = "Application ID of the module-managed Application Insights component for API queries and dashboards."
  value       = local.create_app_insights ? azurerm_application_insights.this[0].app_id : null
}

output "application_insights_connection_string" {
  description = "Application Insights connection string injected into the Web App."
  value       = local.app_insights_connection_string
  sensitive   = true
}
