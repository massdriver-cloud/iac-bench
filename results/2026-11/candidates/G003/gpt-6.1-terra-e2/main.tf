resource "azurerm_resource_group" "service" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

resource "azurerm_log_analytics_workspace" "service" {
  name                = "${var.name}-logs"
  location            = azurerm_resource_group.service.location
  resource_group_name = azurerm_resource_group.service.name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days
  tags                = var.tags
}

resource "azurerm_application_insights" "service" {
  name                = "${var.name}-insights"
  location            = azurerm_resource_group.service.location
  resource_group_name = azurerm_resource_group.service.name
  workspace_id        = azurerm_log_analytics_workspace.service.id
  application_type    = "web"
  tags                = var.tags
}

resource "azurerm_service_plan" "service" {
  name                   = "${var.name}-plan"
  location               = azurerm_resource_group.service.location
  resource_group_name    = azurerm_resource_group.service.name
  os_type                = "Linux"
  sku_name               = var.sku_name
  worker_count           = var.minimum_instances
  zone_balancing_enabled = var.zone_balancing_enabled
  tags                   = var.tags

  # Autoscale owns the live worker count after initial creation.
  lifecycle {
    ignore_changes = [worker_count]
  }
}

locals {
  settings = merge(var.app_settings, {
    WEBSITES_PORT                         = tostring(var.container_port)
    APPLICATIONINSIGHTS_CONNECTION_STRING = azurerm_application_insights.service.connection_string
  })
}

resource "azurerm_linux_web_app" "service" {
  name                                           = var.name
  location                                       = azurerm_resource_group.service.location
  resource_group_name                            = azurerm_resource_group.service.name
  service_plan_id                                = azurerm_service_plan.service.id
  https_only                                     = true
  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = false
  tags                                           = var.tags
  app_settings                                   = local.settings

  identity {
    type = "SystemAssigned"
  }

  site_config {
    always_on                               = true
    ftps_state                              = "Disabled"
    minimum_tls_version                     = "1.2"
    http2_enabled                           = true
    health_check_path                       = var.health_check_path
    health_check_eviction_time_in_min       = 2
    container_registry_use_managed_identity = var.registry_use_managed_identity
    application_stack {
      docker_image_name   = var.image
      docker_registry_url = var.registry_url
    }
  }
}

resource "azurerm_linux_web_app_slot" "staging" {
  count                                          = var.enable_staging_slot ? 1 : 0
  name                                           = "staging"
  app_service_id                                 = azurerm_linux_web_app.service.id
  https_only                                     = true
  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = false
  tags                                           = var.tags
  app_settings                                   = local.settings

  identity {
    type = "SystemAssigned"
  }

  site_config {
    always_on                               = true
    ftps_state                              = "Disabled"
    minimum_tls_version                     = "1.2"
    http2_enabled                           = true
    health_check_path                       = var.health_check_path
    health_check_eviction_time_in_min       = 2
    container_registry_use_managed_identity = var.registry_use_managed_identity
    application_stack {
      docker_image_name   = coalesce(var.staging_image, var.image)
      docker_registry_url = var.registry_url
    }
  }
}

resource "azurerm_monitor_autoscale_setting" "service" {
  name                = "${var.name}-autoscale"
  location            = azurerm_resource_group.service.location
  resource_group_name = azurerm_resource_group.service.name
  target_resource_id  = azurerm_service_plan.service.id
  tags                = var.tags

  profile {
    name = "cpu"
    capacity {
      default = var.minimum_instances
      minimum = var.minimum_instances
      maximum = var.maximum_instances
    }
    rule {
      metric_trigger {
        metric_name        = "CpuPercentage"
        metric_resource_id = azurerm_service_plan.service.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
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
        metric_resource_id = azurerm_service_plan.service.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT10M"
        time_aggregation   = "Average"
        operator           = "LessThan"
        threshold          = 30
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

resource "azurerm_monitor_diagnostic_setting" "app" {
  name                       = "${var.name}-diagnostics"
  target_resource_id         = azurerm_linux_web_app.service.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.service.id
  enabled_log { category = "AppServiceHTTPLogs" }
  enabled_log { category = "AppServiceConsoleLogs" }
  enabled_log { category = "AppServiceAppLogs" }
  enabled_metric { category = "AllMetrics" }
}

resource "azurerm_monitor_diagnostic_setting" "staging" {
  count                      = var.enable_staging_slot ? 1 : 0
  name                       = "${var.name}-staging-diagnostics"
  target_resource_id         = azurerm_linux_web_app_slot.staging[0].id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.service.id
  enabled_log { category = "AppServiceHTTPLogs" }
  enabled_log { category = "AppServiceConsoleLogs" }
  enabled_log { category = "AppServiceAppLogs" }
  enabled_metric { category = "AllMetrics" }
}
