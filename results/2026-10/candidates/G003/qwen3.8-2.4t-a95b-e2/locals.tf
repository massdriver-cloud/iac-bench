locals {
  resource_group_name = coalesce(var.resource_group_name, "${var.service_name}-rg")

  # Standard tags every resource carries; var.tags wins on conflict.
  common_tags = merge(
    {
      service     = var.service_name
      environment = var.environment
      managed-by  = "opentofu"
      module      = "standard-app-service"
    },
    var.tags,
  )

  # Public health endpoint, used by the availability test and handy as output.
  health_check_url = "https://${azurerm_linux_web_app.this.default_hostname}${var.health_check_path}"

  # Settings every instance of the service gets (production slot and staging
  # slot alike). Order matters: user extras first, module-managed keys last so
  # the standard wiring can never be silently overridden.
  app_settings = merge(
    var.additional_app_settings,
    {
      # Observability: route the app into the service's Application Insights.
      APPLICATIONINSIGHTS_CONNECTION_STRING = azurerm_application_insights.this.connection_string
      APPINSIGHTS_INSTRUMENTATIONKEY        = azurerm_application_insights.this.instrumentation_key

      # Health: restart + drain an instance after N failed pings.
      WEBSITE_HEALTHCHECK_MAXPINGFAILURES = tostring(var.health_check_max_ping_failures)
    },
    var.container_port != null ? { WEBSITES_PORT = tostring(var.container_port) } : {},
    var.container_registry_username != null ? { DOCKER_REGISTRY_SERVER_USERNAME = var.container_registry_username } : {},
    var.container_registry_password != null ? { DOCKER_REGISTRY_SERVER_PASSWORD = var.container_registry_password } : {},
    var.vnet_integration_subnet_id != null ? { WEBSITE_VNET_ROUTE_ALL = "1" } : {},
  )

  # App settings that survive slot swaps untouched: App Insights wiring
  # follows the slot that currently serves production.
  sticky_app_setting_names = [
    "APPLICATIONINSIGHTS_CONNECTION_STRING",
    "APPINSIGHTS_INSTRUMENTATIONKEY",
  ]

  # Managed-identity image pulls: grant AcrPull to every identity that pulls.
  acr_pull_principals = {
    for name, principal_id in {
      app  = azurerm_linux_web_app.this.identity[0].principal_id
      slot = var.staging_slot_enabled ? one(azurerm_linux_web_app_slot.staging[*].identity[0].principal_id) : null
    } : name => principal_id
    if var.pull_with_managed_identity && var.container_registry_resource_id != null && principal_id != null
  }

  # Classic URL-ping availability test definition, aimed at the health endpoint.
  availability_test_configuration = <<-EOT
    <WebTest Name="${var.service_name}-availability" Enabled="True" CssProjectStructure="" CssIteration="" Timeout="0" WorkItemIds="" xmlns="http://microsoft.com/schemas/VisualStudio/TeamTest/2010" Description="Standard availability ping for ${var.service_name}" CredentialUserName="" CredentialPassword="" PreAuthenticate="True" Proxy="default" StopOnError="False" RecordedResultFile="" ResultsLocale="">
      <Items>
        <Request Method="GET" Guid="d1c9b4c2-7a4e-4c8f-9b2a-6f0e8d3c5a17" Version="1.1" Url="${local.health_check_url}" ThinkTime="0" Timeout="${var.availability_test_timeout_seconds}" ParseDependentRequests="False" FollowRedirects="True" RecordResult="True" Cache="False" ResponseTimeGoal="0" Encoding="utf-8" ExpectedHttpStatusCode="${var.availability_test_expected_status_code}" ExpectedResponseUrl="" ReportingName="" IgnoreHttpStatusCode="False" />
      </Items>
    </WebTest>
  EOT
}
