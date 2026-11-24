output "resource_group_name" {
  description = "Name of the Resource Group hosting the service."
  value       = local.resource_group_name
}

output "app_id" {
  description = "Azure Resource Manager ID of the production Linux Web App."
  value       = azurerm_linux_web_app.this.id
}

output "app_name" {
  description = "Name of the production Linux Web App (used by CI/CD deployment commands)."
  value       = azurerm_linux_web_app.this.name
}

output "default_hostname" {
  description = "Default FQDN of the production Linux Web App."
  value       = azurerm_linux_web_app.this.default_hostname
}

output "production_url" {
  description = "HTTPS base URL of the production HTTP API."
  value       = "https://${azurerm_linux_web_app.this.default_hostname}"
}

output "health_check_url" {
  description = "HTTPS health probe URL of the production HTTP API."
  value       = "https://${azurerm_linux_web_app.this.default_hostname}${var.health.path}"
}

output "custom_domain_verification_id" {
  description = "Domain verification token required for binding custom DNS hostnames (`asuid.<hostname>` TXT record)."
  value       = azurerm_linux_web_app.this.custom_domain_verification_id
  sensitive   = true
}

output "outbound_ip_addresses" {
  description = "List of active outbound IPv4 addresses used by the Web App."
  value       = azurerm_linux_web_app.this.outbound_ip_address_list
}

output "possible_outbound_ip_addresses" {
  description = "Superset of all possible outbound IPv4 addresses across scale/SKU operations for downstream firewall allowlists."
  value       = azurerm_linux_web_app.this.possible_outbound_ip_address_list
}

output "identity" {
  description = "Managed Identity details for granting downstream Azure RBAC permissions (databases, Service Bus, Storage, Key Vault)."
  value = {
    principal_id               = azurerm_linux_web_app.this.identity[0].principal_id
    tenant_id                  = azurerm_linux_web_app.this.identity[0].tenant_id
    user_assigned_identity_ids = var.user_assigned_identity_ids
  }
}

output "staging_slot" {
  description = "Staging deployment slot metadata for blue/green rollouts and warmup-gated swaps (null when disabled)."
  value = local.effective_staging_slot_enabled ? {
    id               = azurerm_linux_web_app_slot.staging[0].id
    name             = azurerm_linux_web_app_slot.staging[0].name
    default_hostname = azurerm_linux_web_app_slot.staging[0].default_hostname
    url              = "https://${azurerm_linux_web_app_slot.staging[0].default_hostname}"
    principal_id     = azurerm_linux_web_app_slot.staging[0].identity[0].principal_id
  } : null
}

output "capacity_posture" {
  description = "Effective compute SKU, zone redundancy, and horizontal scaling configuration."
  value = {
    service_plan_id   = local.service_plan_id
    sku_name          = var.capacity.sku_name
    zone_redundant    = local.effective_zone_redundant
    autoscale_enabled = local.effective_autoscale_enabled
    min_instances     = var.capacity.min_instances
    max_instances     = var.capacity.max_instances
  }
}

output "private_endpoint_ip" {
  description = "Private IPv4 address of the Web App's Private Endpoint, or null when Private Endpoint is not enabled."
  value       = var.network.private_endpoint_subnet_id != null ? azurerm_private_endpoint.this[0].private_service_connection[0].private_ip_address : null
}

output "observability" {
  description = "Log Analytics, Application Insights, and Azure Monitor alerting resource identifiers."
  value = {
    log_analytics_workspace_id  = local.log_analytics_workspace_id
    application_insights_id     = var.observability.application_insights_enabled ? azurerm_application_insights.this[0].id : null
    application_insights_app_id = var.observability.application_insights_enabled ? azurerm_application_insights.this[0].app_id : null
    action_group_ids            = local.effective_action_group_ids
    alert_ids = compact([
      try(azurerm_monitor_metric_alert.http_5xx[0].id, ""),
      try(azurerm_monitor_metric_alert.response_time[0].id, ""),
      try(azurerm_monitor_metric_alert.health_check[0].id, ""),
      try(azurerm_monitor_metric_alert.cpu_saturation[0].id, ""),
      try(azurerm_monitor_metric_alert.memory_saturation[0].id, ""),
    ])
  }
}

output "application_insights_connection_string" {
  description = "Application Insights connection string injected into the container runtime (null when disabled)."
  value       = var.observability.application_insights_enabled ? azurerm_application_insights.this[0].connection_string : null
  sensitive   = true
}
