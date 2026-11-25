output "service_url" {
  description = "Public HTTPS endpoint of the service."
  value       = "https://${azurerm_linux_web_app.this.default_hostname}"
}

output "default_hostname" {
  description = "Default hostname of the production app (the service_url host)."
  value       = azurerm_linux_web_app.this.default_hostname
}

output "web_app_id" {
  description = "Resource ID of the production web app."
  value       = azurerm_linux_web_app.this.id
}

output "web_app_name" {
  description = "Name of the production web app."
  value       = azurerm_linux_web_app.this.name
}

output "app_service_plan_id" {
  description = "Resource ID of the App Service plan carrying this service."
  value       = azurerm_service_plan.this.id
}

output "resource_group_name" {
  description = "Resource group containing every resource of this service."
  value       = azurerm_resource_group.this.name
}

output "staging_slot_hostname" {
  description = "Hostname of the warm staging slot, or null when enable_staging_slot = false. Deploy candidate builds here before promoting them."
  value       = var.enable_staging_slot ? azurerm_linux_web_app_slot.staging[0].default_hostname : null
}

output "staging_promote_command" {
  description = "Zero-downtime promotion: swaps the (healthy, warm) staging slot into production."
  value       = "az webapp deployment slot swap --resource-group ${azurerm_resource_group.this.name} --name ${azurerm_linux_web_app.this.name} --slot staging --target-slot production"
}

output "log_analytics_workspace_id" {
  description = "Log Analytics workspace collecting platform, HTTP, console and audit logs of this service."
  value       = azurerm_log_analytics_workspace.this.id
}

output "application_insights_connection_string" {
  description = "Connection string injected into the container as APPLICATIONINSIGHTS_CONNECTION_STRING. Hand it to your SDK's Azure Monitor exporter to get request, dependency and exception telemetry."
  value       = azurerm_application_insights.this.connection_string
  sensitive   = true
}

output "identity_principal_id" {
  description = "Principal ID of the system-assigned identity of the production app. Use it to grant the service access to Key Vault, databases or queues."
  value       = azurerm_linux_web_app.this.identity[0].principal_id
}

output "capacity" {
  description = "Effective capacity posture of this deployment."
  value = {
    instance_size = var.instance_size
    sku           = local.sku_by_size[var.instance_size]
    min_instances = var.min_instances
    max_instances = var.max_instances
  }
}
