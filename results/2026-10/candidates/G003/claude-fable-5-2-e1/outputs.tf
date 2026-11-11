output "resource_group_name" {
  description = "Resource group holding the service."
  value       = local.resource_group_name
}

output "app_id" {
  description = "Resource ID of the web app (e.g. as a Front Door / Application Gateway origin, or for extra alerts)."
  value       = azurerm_linux_web_app.this.id
}

output "app_name" {
  description = "Name of the web app."
  value       = azurerm_linux_web_app.this.name
}

output "default_hostname" {
  description = "Default hostname of the production app."
  value       = azurerm_linux_web_app.this.default_hostname
}

output "url" {
  description = "HTTPS URL of the production app."
  value       = "https://${azurerm_linux_web_app.this.default_hostname}"
}

output "staging_hostname" {
  description = "Hostname of the staging slot. Between releases it serves the previous release (the rollback target)."
  value       = azurerm_linux_web_app_slot.staging.default_hostname
}

output "released_image" {
  description = "Image this configuration last released to production."
  value       = terraform_data.release.output.image
}

output "rollback_command" {
  description = "Emergency rollback: swaps the previous release (kept warm in the staging slot) back into production in seconds. Afterwards set `image` back to the previous version so code and reality agree."
  value       = "az webapp deployment slot swap --resource-group ${local.resource_group_name} --name ${azurerm_linux_web_app.this.name} --slot staging --target-slot production"
}

output "service_plan_id" {
  description = "Resource ID of the service's App Service plan."
  value       = azurerm_service_plan.this.id
}

output "identity_id" {
  description = "Resource ID of the service's user-assigned managed identity."
  value       = azurerm_user_assigned_identity.this.id
}

output "identity_principal_id" {
  description = "Object ID of the service's managed identity. Grant this principal access to the databases, queues, vaults etc. the service calls."
  value       = azurerm_user_assigned_identity.this.principal_id
}

output "identity_client_id" {
  description = "Client ID of the service's managed identity (also injected into the container as AZURE_CLIENT_ID)."
  value       = azurerm_user_assigned_identity.this.client_id
}

output "outbound_ip_addresses" {
  description = "Every IP the app may use for outbound calls when not VNet-integrated - for downstream firewall allow-lists."
  value       = split(",", azurerm_linux_web_app.this.possible_outbound_ip_addresses)
}

output "log_analytics_workspace_id" {
  description = "Log Analytics workspace receiving the service's logs and metrics."
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

output "private_endpoint_ip" {
  description = "Private IP of the app's private endpoint, or null when none is configured."
  value       = try(azurerm_private_endpoint.app[0].private_service_connection[0].private_ip_address, null)
}
