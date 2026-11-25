output "resource_group_name" {
  description = "Resource group containing the service."
  value       = local.resource_group_name
}

output "app_id" {
  description = "Resource ID of the web app."
  value       = azurerm_linux_web_app.this.id
}

output "app_name" {
  description = "Name of the web app."
  value       = azurerm_linux_web_app.this.name
}

output "url" {
  description = "Production URL of the service (default host name)."
  value       = "https://${azurerm_linux_web_app.this.default_hostname}"
}

output "staging_url" {
  description = "URL of the staging slot, where a new image runs before it is swapped into production."
  value       = "https://${azurerm_linux_web_app_slot.staging.default_hostname}"
}

output "ingress_mode" {
  description = "Effective network exposure of the app: private, restricted or public."
  value       = var.ingress.mode
}

output "rollout" {
  description = "How to promote the image staged by the last apply, and how to roll it back."
  value = {
    staged_image     = "${var.image.registry}/${local.docker_image_name}"
    staging_url      = "https://${azurerm_linux_web_app_slot.staging.default_hostname}"
    promote_command  = "az webapp deployment slot swap --resource-group ${local.resource_group_name} --name ${azurerm_linux_web_app.this.name} --slot ${local.slot_name} --target-slot production"
    rollback_command = "az webapp deployment slot swap --resource-group ${local.resource_group_name} --name ${azurerm_linux_web_app.this.name} --slot ${local.slot_name} --target-slot production"
    note             = "Promote and rollback are the same swap: until the next apply, the staging slot holds the previously live release."
  }
}

output "service_plan_id" {
  description = "Resource ID of the App Service plan."
  value       = azurerm_service_plan.this.id
}

output "identity" {
  description = "User-assigned managed identity the app runs as. Grant this principal access to the service's dependencies (databases, storage, queues, ...)."
  value = {
    id           = azurerm_user_assigned_identity.this.id
    client_id    = azurerm_user_assigned_identity.this.client_id
    principal_id = azurerm_user_assigned_identity.this.principal_id
  }
}

output "possible_outbound_ip_addresses" {
  description = "Every public IP the app may use for outbound calls when it is not routed through a VNet; use for allow-listing on dependencies."
  value       = azurerm_linux_web_app.this.possible_outbound_ip_address_list
}

output "private_endpoint_ips" {
  description = "Private IP addresses of the production and staging private endpoints (null when none are created)."
  value = local.create_private_endpoints ? {
    production = azurerm_private_endpoint.app[0].private_service_connection[0].private_ip_address
    staging    = azurerm_private_endpoint.staging[0].private_service_connection[0].private_ip_address
  } : null
}

output "log_analytics_workspace_id" {
  description = "Log Analytics workspace receiving the service's logs."
  value       = local.log_analytics_workspace_id
}

output "application_insights_id" {
  description = "Resource ID of the Application Insights component (null when disabled)."
  value       = one(azurerm_application_insights.this[*].id)
}

output "application_insights_connection_string" {
  description = "Application Insights connection string (null when disabled). Already injected into the container."
  value       = one(azurerm_application_insights.this[*].connection_string)
  sensitive   = true
}

output "alert_rule_ids" {
  description = "Metric alert rule IDs by name."
  value       = { for k, v in azurerm_monitor_metric_alert.this : k => v.id }
}
