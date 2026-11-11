locals {
  resource_group_name = var.create_resource_group ? azurerm_resource_group.this[0].name : var.resource_group_name

  tags = merge(
    var.tags,
    {
      managed_by = "opentofu"
      module     = "sre-app-service"
      service    = var.name
    },
  )

  plan_name             = substr("${var.name}-plan", 0, 40)
  workspace_name        = substr("${var.name}-law", 0, 63)
  app_insights_name     = substr("${var.name}-ai", 0, 250)
  identity_name         = substr("${var.name}-id", 0, 120)
  action_group_name     = substr("${var.name}-alerts", 0, 250)
  autoscale_name        = substr("${var.name}-autoscale", 0, 250)
  private_endpoint_name = substr("${var.name}-pep", 0, 80)

  log_analytics_workspace_id = var.log_analytics_workspace_id != null ? var.log_analytics_workspace_id : azurerm_log_analytics_workspace.this[0].id

  managed_app_settings = {
    APPINSIGHTS_INSTRUMENTATIONKEY        = azurerm_application_insights.this.instrumentation_key
    APPLICATIONINSIGHTS_CONNECTION_STRING = azurerm_application_insights.this.connection_string
    WEBSITES_CONTAINER_START_TIME_LIMIT   = tostring(var.container_start_time_limit)
    WEBSITES_ENABLE_APP_SERVICE_STORAGE   = "false"
    WEBSITES_PORT                         = tostring(var.container_port)
  }

  production_app_settings = merge(var.app_settings, local.managed_app_settings)
  staging_app_settings    = merge(var.app_settings, var.staging_app_settings, local.managed_app_settings)

  staging_image = var.staging_container_image != null ? var.staging_container_image : var.container_image

  alert_action_group_ids = concat(var.alert_action_group_ids, azurerm_monitor_action_group.this[*].id)

  # External App Insights agents cannot reach private endpoints or arbitrary CIDR allow lists.
  availability_test_active = var.availability_test_enabled && var.public_network_access_enabled && length(var.allowed_source_cidrs) == 0

  metric_alerts = {
    http_5xx = {
      description      = "Production app returned more than the configured number of HTTP 5xx responses in five minutes."
      metric_name      = "Http5xx"
      metric_namespace = "Microsoft.Web/sites"
      scope_id         = azurerm_linux_web_app.this.id
      aggregation      = "Total"
      operator         = "GreaterThan"
      threshold        = var.http_5xx_alert_threshold
      severity         = 2
      frequency        = "PT1M"
      window_size      = "PT5M"
    }
    health_check = {
      description      = "At least one production instance is failing the App Service health check."
      metric_name      = "HealthCheckStatus"
      metric_namespace = "Microsoft.Web/sites"
      scope_id         = azurerm_linux_web_app.this.id
      aggregation      = "Average"
      operator         = "LessThan"
      threshold        = 1
      severity         = 1
      frequency        = "PT1M"
      window_size      = "PT5M"
    }
    response_time = {
      description      = "Production average response time exceeded its 15-minute budget."
      metric_name      = "HttpResponseTime"
      metric_namespace = "Microsoft.Web/sites"
      scope_id         = azurerm_linux_web_app.this.id
      aggregation      = "Average"
      operator         = "GreaterThan"
      threshold        = var.response_time_alert_threshold_seconds
      severity         = 3
      frequency        = "PT5M"
      window_size      = "PT15M"
    }
    cpu = {
      description      = "App Service plan CPU remained above its alerting threshold."
      metric_name      = "CpuPercentage"
      metric_namespace = "Microsoft.Web/serverfarms"
      scope_id         = azurerm_service_plan.this.id
      aggregation      = "Average"
      operator         = "GreaterThan"
      threshold        = var.cpu_alert_threshold
      severity         = 3
      frequency        = "PT5M"
      window_size      = "PT15M"
    }
    memory = {
      description      = "App Service plan memory remained above its alerting threshold."
      metric_name      = "MemoryPercentage"
      metric_namespace = "Microsoft.Web/serverfarms"
      scope_id         = azurerm_service_plan.this.id
      aggregation      = "Average"
      operator         = "GreaterThan"
      threshold        = var.memory_alert_threshold
      severity         = 3
      frequency        = "PT5M"
      window_size      = "PT15M"
    }
  }
}
