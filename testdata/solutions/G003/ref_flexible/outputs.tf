output "app_name" {
  description = "Name of the web app."
  value       = azurerm_linux_web_app.this.name
}

output "default_hostname" {
  description = "Default HTTPS hostname of the web app."
  value       = azurerm_linux_web_app.this.default_hostname
}

output "principal_id" {
  description = "Object ID of the app's managed identity, for granting it access to other resources."
  value       = azurerm_linux_web_app.this.identity[0].principal_id
}

output "log_analytics_workspace_id" {
  description = "Workspace receiving the app's diagnostic logs."
  value       = azurerm_log_analytics_workspace.this.id
}
