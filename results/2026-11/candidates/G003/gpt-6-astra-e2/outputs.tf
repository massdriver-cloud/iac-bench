output "resource_group_name" {
  description = "Dedicated resource group."
  value       = azurerm_resource_group.this.name
}

output "app_name" {
  description = "Production application name for deployment tooling."
  value       = azurerm_linux_web_app.production.name
}

output "app_id" {
  description = "Production App Service resource ID."
  value       = azurerm_linux_web_app.production.id
}

output "production_url" {
  description = "Production HTTPS endpoint."
  value       = "https://${azurerm_linux_web_app.production.default_hostname}"
}

output "staging_url" {
  description = "Staging endpoint (allowlisted management CIDRs only); null when disabled."
  value       = var.enable_staging_slot ? "https://${azurerm_linux_web_app_slot.staging[0].default_hostname}" : null
}

output "staging_slot_id" {
  description = "Staging slot resource ID; null when disabled."
  value       = var.enable_staging_slot ? azurerm_linux_web_app_slot.staging[0].id : null
}

output "service_plan_id" {
  description = "Dedicated Linux service plan ID."
  value       = azurerm_service_plan.this.id
}

output "identities" {
  description = "Slot-isolated user-assigned identities used for registry pulls and Key Vault references. Grant these Key Vault Secrets User on the required vaults, not subscription-wide."
  value = {
    for environment, identity in azurerm_user_assigned_identity.app : environment => {
      id           = identity.id
      client_id    = identity.client_id
      principal_id = identity.principal_id
    }
  }
}

output "runtime_principal_ids" {
  description = "Per-slot system-assigned principals used by default Azure SDK managed identity authentication. Grant least-privilege access to application dependencies."
  value = merge(
    { production = azurerm_linux_web_app.production.identity[0].principal_id },
    var.enable_staging_slot ? { staging = azurerm_linux_web_app_slot.staging[0].identity[0].principal_id } : {}
  )
}

output "log_analytics_workspace_id" {
  description = "Central log workspace resource ID."
  value       = azurerm_log_analytics_workspace.this.id
}

output "application_insights_ids" {
  description = "Per-environment Application Insights resource IDs. Containers must instrument requests with an SDK or OpenTelemetry exporter."
  value       = { for environment, insights in azurerm_application_insights.app : environment => insights.id }
}

output "action_group_id" {
  description = "SRE action group for additional service-specific alerts."
  value       = azurerm_monitor_action_group.sre.id
}
