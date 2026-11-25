output "resource_group_name" {
  description = "Resource group dedicated to this service."
  value       = azurerm_resource_group.this.name
}

output "app_name" {
  description = "Production App Service name (use with deployment tooling)."
  value       = azurerm_linux_web_app.this.name
}

output "app_id" {
  description = "Production app resource ID."
  value       = azurerm_linux_web_app.this.id
}

output "production_url" {
  description = "Azure-provided HTTPS endpoint; custom domains and certificates are managed separately."
  value       = "https://${azurerm_linux_web_app.this.default_hostname}"
}

output "staging_url" {
  description = "Staging HTTPS endpoint, or null when staging is disabled."
  value       = var.staging.enabled ? "https://${azurerm_linux_web_app_slot.staging[0].default_hostname}" : null
}

output "staging_slot_id" {
  description = "Staging resource ID, or null."
  value       = var.staging.enabled ? azurerm_linux_web_app_slot.staging[0].id : null
}

output "service_plan_id" {
  description = "Dedicated Linux plan resource ID."
  value       = azurerm_service_plan.this.id
}

output "identity" {
  description = "Shared production/staging managed identity. Grant only necessary Key Vault/data-plane roles externally."
  value = {
    id           = azurerm_user_assigned_identity.app.id
    client_id    = azurerm_user_assigned_identity.app.client_id
    principal_id = azurerm_user_assigned_identity.app.principal_id
  }
}

output "observability" {
  description = "Azure Monitor resource IDs for dashboards, queries and incident routing."
  value = {
    workspace_id            = azurerm_log_analytics_workspace.this.id
    application_insights_id = azurerm_application_insights.this.id
    action_group_id         = azurerm_monitor_action_group.sre.id
  }
}

output "application_insights_connection_string" {
  description = "SDK connection string, also injected into both containers."
  value       = azurerm_application_insights.this.connection_string
  sensitive   = true
}

output "possible_outbound_ip_addresses" {
  description = "Potential egress IPs, not a fixed egress guarantee. Use VNet integration and an externally managed NAT Gateway for stable egress."
  value       = azurerm_linux_web_app.this.possible_outbound_ip_address_list
}
