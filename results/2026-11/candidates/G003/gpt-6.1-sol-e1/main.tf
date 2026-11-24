locals {
  platform_settings = {
    WEBSITES_PORT                         = tostring(var.container_port)
    WEBSITES_ENABLE_APP_SERVICE_STORAGE   = "false"
    WEBSITE_HEALTHCHECK_MAXPINGFAILURES   = "3"
    WEBSITE_WARMUP_PATH                   = var.health_check_path
    WEBSITE_WARMUP_STATUSES               = "200"
    WEBSITE_SWAP_WARMUP_PING_PATH         = var.health_check_path
    WEBSITE_SWAP_WARMUP_PING_STATUSES     = "200"
    APPLICATIONINSIGHTS_CONNECTION_STRING = azurerm_application_insights.this.connection_string
  }
  production_settings = merge(var.app_settings, var.slot_settings.production, local.platform_settings)
  staging_settings    = merge(var.app_settings, var.slot_settings.staging, local.platform_settings)
  sticky_keys         = nonsensitive(keys(var.slot_settings.production))
}

resource "azurerm_resource_group" "this" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

resource "azurerm_service_plan" "this" {
  name                   = "${var.name}-plan"
  resource_group_name    = azurerm_resource_group.this.name
  location               = azurerm_resource_group.this.location
  os_type                = "Linux"
  sku_name               = var.sku_name
  worker_count           = var.capacity.default
  zone_balancing_enabled = var.zone_balancing_enabled
  tags                   = var.tags

  lifecycle {
    ignore_changes = [worker_count]
    precondition {
      condition     = !var.zone_balancing_enabled || var.capacity.minimum >= 3
      error_message = "Zone balancing requires at least three workers."
    }
    precondition {
      condition     = length(setintersection(toset([for k in nonsensitive(keys(var.app_settings)) : upper(k)]), toset([for k in local.sticky_keys : upper(k)]))) == 0
      error_message = "Shared app_settings and slot_settings must not overlap."
    }
    precondition {
      condition = alltrue([for k in concat(nonsensitive(keys(var.app_settings)), local.sticky_keys) : !contains([
        "WEBSITE_WARMUP_PATH", "WEBSITE_WARMUP_STATUSES", "WEBSITE_SWAP_WARMUP_PING_PATH", "WEBSITE_SWAP_WARMUP_PING_STATUSES"
      ], upper(k))])
      error_message = "Warmup settings are owned by the module and cannot be overridden."
    }
  }
}

resource "azurerm_log_analytics_workspace" "this" {
  name                = "${var.name}-logs"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = var.tags
}

resource "azurerm_application_insights" "this" {
  name                = "${var.name}-insights"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  workspace_id        = azurerm_log_analytics_workspace.this.id
  application_type    = "web"
  retention_in_days   = 30
  tags                = var.tags
}

resource "azurerm_linux_web_app" "this" {
  name                                           = var.name
  resource_group_name                            = azurerm_resource_group.this.name
  location                                       = azurerm_resource_group.this.location
  service_plan_id                                = azurerm_service_plan.this.id
  https_only                                     = true
  public_network_access_enabled                  = true
  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = false
  virtual_network_subnet_id                      = var.integration_subnet_id
  app_settings                                   = local.production_settings
  tags                                           = var.tags

  identity { type = "SystemAssigned" }

  site_config {
    always_on                               = true
    http2_enabled                           = true
    ftps_state                              = "Disabled"
    minimum_tls_version                     = "1.2"
    scm_minimum_tls_version                 = "1.2"
    health_check_path                       = var.health_check_path
    health_check_eviction_time_in_min       = 5
    container_registry_use_managed_identity = var.acr_resource_id != null
    vnet_route_all_enabled                  = var.integration_subnet_id != null
    application_stack {
      docker_image_name   = var.image
      docker_registry_url = var.registry_url
    }
  }

  dynamic "sticky_settings" {
    for_each = length(local.sticky_keys) == 0 ? [] : [1]
    content { app_setting_names = local.sticky_keys }
  }

  logs {
    application_logs { file_system_level = "Information" }
    http_logs {
      file_system {
        retention_in_days = 7
        retention_in_mb   = 35
      }
    }
    detailed_error_messages = false
    failed_request_tracing  = false
  }
}

resource "azurerm_linux_web_app_slot" "staging" {
  count                                          = var.staging_enabled ? 1 : 0
  name                                           = "staging"
  app_service_id                                 = azurerm_linux_web_app.this.id
  https_only                                     = true
  public_network_access_enabled                  = true
  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = false
  virtual_network_subnet_id                      = var.integration_subnet_id
  app_settings                                   = local.staging_settings
  tags                                           = var.tags

  identity { type = "SystemAssigned" }

  site_config {
    always_on                               = true
    http2_enabled                           = true
    ftps_state                              = "Disabled"
    minimum_tls_version                     = "1.2"
    scm_minimum_tls_version                 = "1.2"
    health_check_path                       = var.health_check_path
    health_check_eviction_time_in_min       = 5
    container_registry_use_managed_identity = var.acr_resource_id != null
    vnet_route_all_enabled                  = var.integration_subnet_id != null
    application_stack {
      docker_image_name   = coalesce(var.staging_image, var.image)
      docker_registry_url = var.registry_url
    }
  }

  logs {
    application_logs { file_system_level = "Information" }
    http_logs {
      file_system {
        retention_in_days = 7
        retention_in_mb   = 35
      }
    }
    detailed_error_messages = false
    failed_request_tracing  = false
  }
}

resource "azurerm_role_assignment" "acr_production" {
  count                = var.acr_resource_id != null ? 1 : 0
  scope                = var.acr_resource_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_linux_web_app.this.identity[0].principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "acr_staging" {
  count                = var.acr_resource_id != null && var.staging_enabled ? 1 : 0
  scope                = var.acr_resource_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_linux_web_app_slot.staging[0].identity[0].principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_monitor_autoscale_setting" "this" {
  name                = "${var.name}-autoscale"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  target_resource_id  = azurerm_service_plan.this.id
  enabled             = true
  tags                = var.tags

  profile {
    name = "cpu"
    capacity {
      minimum = tostring(var.capacity.minimum)
      default = tostring(var.capacity.default)
      maximum = tostring(var.capacity.maximum)
    }
    rule {
      metric_trigger {
        metric_name        = "CpuPercentage"
        metric_resource_id = azurerm_service_plan.this.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT10M"
        time_aggregation   = "Average"
        operator           = "GreaterThan"
        threshold          = 70
      }
      scale_action {
        direction = "Increase"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT5M"
      }
    }
    rule {
      metric_trigger {
        metric_name        = "CpuPercentage"
        metric_resource_id = azurerm_service_plan.this.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT15M"
        time_aggregation   = "Average"
        operator           = "LessThan"
        threshold          = 35
      }
      scale_action {
        direction = "Decrease"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT10M"
      }
    }
  }
}

resource "azurerm_monitor_diagnostic_setting" "production" {
  name                       = "central-logs"
  target_resource_id         = azurerm_linux_web_app.this.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id

  dynamic "enabled_log" {
    for_each = toset(["AppServiceHTTPLogs", "AppServiceConsoleLogs", "AppServiceAppLogs", "AppServicePlatformLogs"])
    content { category = enabled_log.value }
  }
  enabled_metric { category = "AllMetrics" }
}

resource "azurerm_monitor_diagnostic_setting" "staging" {
  count                      = var.staging_enabled ? 1 : 0
  name                       = "central-logs"
  target_resource_id         = azurerm_linux_web_app_slot.staging[0].id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id

  dynamic "enabled_log" {
    for_each = toset(["AppServiceHTTPLogs", "AppServiceConsoleLogs", "AppServiceAppLogs", "AppServicePlatformLogs"])
    content { category = enabled_log.value }
  }
  enabled_metric { category = "AllMetrics" }
}

resource "azurerm_monitor_metric_alert" "errors" {
  name                = "${var.name}-http5xx"
  resource_group_name = azurerm_resource_group.this.name
  scopes              = [azurerm_linux_web_app.this.id]
  description         = "More than 10 HTTP 5xx responses in five minutes on production."
  severity            = 1
  frequency           = "PT1M"
  window_size         = "PT5M"
  tags                = var.tags
  criteria {
    metric_namespace = "Microsoft.Web/sites"
    metric_name      = "Http5xx"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = 10
  }
  dynamic "action" {
    for_each = var.alert_action_group_ids
    content { action_group_id = action.value }
  }
}

resource "azurerm_monitor_metric_alert" "cpu" {
  name                = "${var.name}-cpu"
  resource_group_name = azurerm_resource_group.this.name
  scopes              = [azurerm_service_plan.this.id]
  description         = "Plan CPU above 85 percent for fifteen minutes; inspect autoscale limits and staging load."
  severity            = 2
  frequency           = "PT1M"
  window_size         = "PT15M"
  tags                = var.tags
  criteria {
    metric_namespace = "Microsoft.Web/serverfarms"
    metric_name      = "CpuPercentage"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 85
  }
  dynamic "action" {
    for_each = var.alert_action_group_ids
    content { action_group_id = action.value }
  }
}

resource "azurerm_monitor_metric_alert" "health" {
  name                = "${var.name}-health"
  resource_group_name = azurerm_resource_group.this.name
  scopes              = [azurerm_linux_web_app.this.id]
  description         = "Production health check status below 1 for five minutes. Investigate container health and dependencies."
  severity            = 1
  frequency           = "PT1M"
  window_size         = "PT5M"
  tags                = var.tags
  criteria {
    metric_namespace = "Microsoft.Web/sites"
    metric_name      = "HealthCheckStatus"
    aggregation      = "Average"
    operator         = "LessThan"
    threshold        = 1
  }
  dynamic "action" {
    for_each = var.alert_action_group_ids
    content { action_group_id = action.value }
  }
}
