output "resource_group_name" {
  description = "Resource group containing the service."
  value       = local.resource_group_name
}

output "web_app_id" {
  description = "Production Linux web app resource ID."
  value       = azurerm_linux_web_app.this.id
}

output "web_app_name" {
  description = "Production Linux web app name."
  value       = azurerm_linux_web_app.this.name
}

output "default_hostname" {
  description = "Production default hostname."
  value       = azurerm_linux_web_app.this.default_hostname
}

output "health_url" {
  description = "Production HTTPS health endpoint."
  value       = "https://${azurerm_linux_web_app.this.default_hostname}${var.health_check_path}"
}

output "outbound_ip_addresses" {
  description = "Current production outbound IP addresses, useful for downstream firewalls."
  value       = split(",", azurerm_linux_web_app.this.outbound_ip_addresses)
}

output "possible_outbound_ip_addresses" {
  description = "All possible production outbound IP addresses, including future scale/region changes."
  value       = split(",", azurerm_linux_web_app.this.possible_outbound_ip_addresses)
}

output "service_plan_id" {
  description = "Linux App Service plan resource ID."
  value       = azurerm_service_plan.this.id
}

output "identity" {
  description = "User-assigned identity shared by production and staging and used for ACR/Key Vault references."
  value = {
    id           = azurerm_user_assigned_identity.this.id
    client_id    = azurerm_user_assigned_identity.this.client_id
    principal_id = azurerm_user_assigned_identity.this.principal_id
    tenant_id    = azurerm_user_assigned_identity.this.tenant_id
  }
}

output "staging_slot" {
  description = "Staging slot identifiers and hostname, or null when slots are disabled."
  value = var.deployment_slot_enabled ? {
    id               = azurerm_linux_web_app_slot.staging[0].id
    name             = azurerm_linux_web_app_slot.staging[0].name
    default_hostname = azurerm_linux_web_app_slot.staging[0].default_hostname
    container_image  = local.staging_image
  } : null
}

output "application_insights" {
  description = "Application Insights resource identifiers."
  value = {
    id   = azurerm_application_insights.this.id
    name = azurerm_application_insights.this.name
  }
}

output "application_insights_connection_string" {
  description = "Connection string for application SDKs that need an explicit telemetry configuration."
  value       = azurerm_application_insights.this.connection_string
  sensitive   = true
}

output "log_analytics_workspace_id" {
  description = "Existing or module-created Log Analytics workspace ID."
  value       = local.log_analytics_workspace_id
}

output "autoscale_setting_id" {
  description = "Autoscale setting resource ID, or null when autoscaling is disabled."
  value       = var.autoscale_enabled ? azurerm_monitor_autoscale_setting.this[0].id : null
}

output "metric_alert_ids" {
  description = "Standard metric alert IDs keyed by alert name."
  value       = { for key, alert in azurerm_monitor_metric_alert.standard : key => alert.id }
}

output "availability_test_id" {
  description = "External health-test ID, or null when the test is disabled or the app is not publicly reachable."
  value       = local.availability_test_active ? azurerm_application_insights_standard_web_test.health[0].id : null
}

output "private_endpoint_id" {
  description = "Production private endpoint ID, or null when not configured."
  value       = var.private_endpoint_subnet_id != null ? azurerm_private_endpoint.production[0].id : null
}
