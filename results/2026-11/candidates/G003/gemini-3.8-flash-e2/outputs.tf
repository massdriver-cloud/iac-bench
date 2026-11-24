output "app_service_id" {
  description = "The Resource ID of the Linux Web App."
  value       = azurerm_linux_web_app.this.id
}

output "app_service_name" {
  description = "The name of the Linux Web App."
  value       = azurerm_linux_web_app.this.name
}

output "default_hostname" {
  description = "The default hostname of the Linux Web App."
  value       = azurerm_linux_web_app.this.default_hostname
}

output "app_url" {
  description = "The HTTPS URL to access the production web service."
  value       = "https://${azurerm_linux_web_app.this.default_hostname}"
}

output "staging_slot_id" {
  description = "The Resource ID of the staging deployment slot, if enabled."
  value       = try(azurerm_linux_web_app_slot.staging[0].id, null)
}

output "staging_slot_hostname" {
  description = "The default hostname of the staging deployment slot, if enabled."
  value       = try(azurerm_linux_web_app_slot.staging[0].default_hostname, null)
}

output "staging_slot_url" {
  description = "The HTTPS URL to access the staging deployment slot, if enabled."
  value       = var.staging_slot_enabled ? "https://${azurerm_linux_web_app_slot.staging[0].default_hostname}" : null
}

output "service_plan_id" {
  description = "The Resource ID of the App Service Plan hosting the application."
  value       = local.service_plan_id
}

output "service_plan_name" {
  description = "The name of the App Service Plan hosting the application."
  value       = var.service_plan_id == null ? azurerm_service_plan.this[0].name : var.service_plan_name
}

output "principal_id" {
  description = "The Principal ID of the System-Assigned Managed Identity of the Web App."
  value       = azurerm_linux_web_app.this.identity[0].principal_id
}

output "tenant_id" {
  description = "The Tenant ID of the System-Assigned Managed Identity of the Web App."
  value       = azurerm_linux_web_app.this.identity[0].tenant_id
}

output "staging_principal_id" {
  description = "The Principal ID of the System-Assigned Managed Identity of the staging deployment slot, if enabled."
  value       = try(azurerm_linux_web_app_slot.staging[0].identity[0].principal_id, null)
}

output "outbound_ip_addresses" {
  description = "A comma-separated list of outbound IP addresses for the Web App."
  value       = azurerm_linux_web_app.this.outbound_ip_addresses
}

output "possible_outbound_ip_addresses" {
  description = "A comma-separated list of all possible outbound IP addresses for the Web App."
  value       = azurerm_linux_web_app.this.possible_outbound_ip_addresses
}

output "autoscale_setting_id" {
  description = "The Resource ID of the Monitor Autoscale Setting, if created."
  value       = try(azurerm_monitor_autoscale_setting.this[0].id, null)
}

output "metric_alert_ids" {
  description = "Map of created Azure Monitor metric alert IDs."
  value = {
    http_5xx      = try(azurerm_monitor_metric_alert.http_5xx[0].id, null)
    response_time = try(azurerm_monitor_metric_alert.response_time[0].id, null)
    health_check  = try(azurerm_monitor_metric_alert.health_check[0].id, null)
    cpu_plan      = try(azurerm_monitor_metric_alert.cpu_plan[0].id, null)
  }
}
