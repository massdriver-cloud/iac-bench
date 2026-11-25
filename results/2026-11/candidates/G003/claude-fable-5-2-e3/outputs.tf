output "resource_group_name" {
  description = "Resource group that holds the service."
  value       = local.resource_group_name
}

output "app_name" {
  description = "Name of the web app (globally unique)."
  value       = azurerm_linux_web_app.this.name
}

output "app_id" {
  description = "Resource ID of the web app, e.g. as a Front Door / Application Gateway origin or for extra alert rules."
  value       = azurerm_linux_web_app.this.id
}

output "url" {
  description = "HTTPS URL of the production slot."
  value       = "https://${azurerm_linux_web_app.this.default_hostname}"
}

output "default_hostname" {
  description = "Default hostname of the production slot."
  value       = azurerm_linux_web_app.this.default_hostname
}

output "health_check_url" {
  description = "URL the platform health check corresponds to on the production slot."
  value       = "https://${azurerm_linux_web_app.this.default_hostname}${var.health_check_path}"
}

output "staging_url" {
  description = "HTTPS URL of the staging slot (null when the slot is disabled)."
  value       = one([for slot in azurerm_linux_web_app_slot.staging : "https://${slot.default_hostname}"])
}

output "swap_command" {
  description = "Command that promotes the staging slot to production (null when the slot is disabled). After swapping, set image to the promoted reference and staging_image back to null."
  value       = var.staging_slot_enabled ? "az webapp deployment slot swap --resource-group ${local.resource_group_name} --name ${azurerm_linux_web_app.this.name} --slot ${local.slot_name} --target-slot production" : null
}

output "service_plan_id" {
  description = "Resource ID of the App Service plan."
  value       = azurerm_service_plan.this.id
}

output "identity_id" {
  description = "Resource ID of the service's user-assigned managed identity."
  value       = azurerm_user_assigned_identity.this.id
}

output "identity_principal_id" {
  description = "Principal (object) ID of the service identity. Grant this principal access to the databases, queues, vaults, ... the service uses."
  value       = azurerm_user_assigned_identity.this.principal_id
}

output "identity_client_id" {
  description = "Client ID of the service identity (also exposed to the container as AZURE_CLIENT_ID)."
  value       = azurerm_user_assigned_identity.this.client_id
}

output "outbound_ip_addresses" {
  description = "All public IPs the service may use for outbound calls when it is not VNet-integrated; use for downstream firewall allow-lists."
  value       = azurerm_linux_web_app.this.possible_outbound_ip_address_list
}

output "log_analytics_workspace_id" {
  description = "Log Analytics workspace that receives the service's logs."
  value       = local.log_analytics_workspace_id
}

output "application_insights_id" {
  description = "Resource ID of the service's Application Insights component."
  value       = azurerm_application_insights.this.id
}

output "application_insights_connection_string" {
  description = "Application Insights connection string (already injected into the container)."
  value       = azurerm_application_insights.this.connection_string
  sensitive   = true
}

output "private_endpoint_ip_address" {
  description = "Private IP of the production private endpoint (null when none is created)."
  value       = one([for pe in azurerm_private_endpoint.app : pe.private_service_connection[0].private_ip_address])
}
