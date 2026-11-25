output "resource_group" {
  description = "Name and resource ID of the resource group containing the service."
  value = {
    name = local.resource_group_name
    id   = local.resource_group_id
  }
}

output "service_plan" {
  description = "App Service plan identifiers and capacity mode."
  value = {
    id                = local.service_plan_id
    name              = local.service_plan_name
    sku_name          = var.plan_sku_name
    autoscale_enabled = var.autoscale_enabled
    zone_balancing    = var.zone_balancing_enabled
  }
}

output "web_app" {
  description = "Production web app identifiers, hostname, URL, and outbound addresses."
  value = {
    id                             = azurerm_linux_web_app.this.id
    name                           = azurerm_linux_web_app.this.name
    default_hostname               = azurerm_linux_web_app.this.default_hostname
    url                            = "https://${azurerm_linux_web_app.this.default_hostname}"
    outbound_ip_addresses          = azurerm_linux_web_app.this.outbound_ip_addresses
    possible_outbound_ip_addresses = azurerm_linux_web_app.this.possible_outbound_ip_addresses
  }
}

output "custom_domain_verification_id" {
  description = "Verification ID for external custom-domain bindings."
  value       = azurerm_linux_web_app.this.custom_domain_verification_id
  sensitive   = true
}

output "staging_slot" {
  description = "Staging slot identifiers and URL, or null when deployment slots are disabled."
  value = var.deployment_slot_enabled ? {
    id               = azurerm_linux_web_app_slot.this[0].id
    name             = azurerm_linux_web_app_slot.this[0].name
    default_hostname = azurerm_linux_web_app_slot.this[0].default_hostname
    url              = "https://${azurerm_linux_web_app_slot.this[0].default_hostname}"
  } : null
}

output "workload_identity" {
  description = "User-assigned identity shared by production and staging. Grant this identity access to application dependencies such as Key Vault and databases."
  value = {
    id           = azurerm_user_assigned_identity.this.id
    client_id    = azurerm_user_assigned_identity.this.client_id
    principal_id = azurerm_user_assigned_identity.this.principal_id
  }
}

output "health_check_path" {
  description = "Configured readiness path, or null when App Service health checks are disabled."
  value       = var.health_check_path
}

output "observability" {
  description = "Log Analytics, Application Insights, autoscale, and alert action group resource IDs."
  value = {
    log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id
    application_insights_id    = azurerm_application_insights.this.id
    autoscale_setting_id       = try(azurerm_monitor_autoscale_setting.this[0].id, null)
    alert_action_group_id      = try(azurerm_monitor_action_group.this[0].id, null)
  }
}

output "application_insights_connection_string" {
  description = "Application Insights connection string for application telemetry. The web app receives this automatically through app settings."
  value       = azurerm_application_insights.this.connection_string
  sensitive   = true
}
