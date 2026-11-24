resource "azurerm_resource_group" "service" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

resource "azurerm_log_analytics_workspace" "service" {
  name                = "${var.service_name}-logs"
  location            = azurerm_resource_group.service.location
  resource_group_name = azurerm_resource_group.service.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = var.tags
}

resource "azurerm_application_insights" "service" {
  name                = "${var.service_name}-insights"
  location            = azurerm_resource_group.service.location
  resource_group_name = azurerm_resource_group.service.name
  application_type    = "web"
  workspace_id        = azurerm_log_analytics_workspace.service.id
  tags                = var.tags
}

resource "azurerm_service_plan" "service" {
  name                = "${var.service_name}-plan"
  location            = azurerm_resource_group.service.location
  resource_group_name = azurerm_resource_group.service.name
  os_type             = "Linux"
  sku_name            = var.sku_name
  worker_count        = var.worker_count
  tags                = var.tags
}

resource "azurerm_linux_web_app" "service" {
  name                                           = var.service_name
  location                                       = azurerm_resource_group.service.location
  resource_group_name                            = azurerm_resource_group.service.name
  service_plan_id                                = azurerm_service_plan.service.id
  https_only                                     = true
  client_affinity_enabled                        = false
  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = false

  identity {
    type = "SystemAssigned"
  }

  app_settings = merge(var.app_settings, {
    WEBSITES_PORT                         = tostring(var.container_port)
    WEBSITES_ENABLE_APP_SERVICE_STORAGE   = "false"
    APPLICATIONINSIGHTS_CONNECTION_STRING = azurerm_application_insights.service.connection_string
    APPLICATIONINSIGHTS_ROLE_NAME         = var.service_name
  })

  site_config {
    always_on                         = true
    http2_enabled                     = true
    minimum_tls_version               = "1.2"
    ftps_state                        = "Disabled"
    health_check_path                 = var.health_check_path
    health_check_eviction_time_in_min = var.health_check_path == null ? null : 2

    application_stack {
      docker_image_name        = var.container_image
      docker_registry_url      = var.docker_registry_url
      docker_registry_username = var.docker_registry_username
      docker_registry_password = var.docker_registry_password
    }
  }

  tags = var.tags
}

# A pre-created staging slot enables production-safe deployments and slot swaps.
resource "azurerm_linux_web_app_slot" "staging" {
  name                                           = "staging"
  app_service_id                                 = azurerm_linux_web_app.service.id
  https_only                                     = true
  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = false

  identity {
    type = "SystemAssigned"
  }

  app_settings = merge(var.app_settings, {
    WEBSITES_PORT                         = tostring(var.container_port)
    WEBSITES_ENABLE_APP_SERVICE_STORAGE   = "false"
    APPLICATIONINSIGHTS_CONNECTION_STRING = azurerm_application_insights.service.connection_string
    APPLICATIONINSIGHTS_ROLE_NAME         = "${var.service_name}-staging"
  })

  site_config {
    always_on                         = true
    http2_enabled                     = true
    minimum_tls_version               = "1.2"
    ftps_state                        = "Disabled"
    health_check_path                 = var.health_check_path
    health_check_eviction_time_in_min = var.health_check_path == null ? null : 2

    application_stack {
      docker_image_name        = var.container_image
      docker_registry_url      = var.docker_registry_url
      docker_registry_username = var.docker_registry_username
      docker_registry_password = var.docker_registry_password
    }
  }

  tags = var.tags
}

resource "azurerm_monitor_autoscale_setting" "service" {
  name                = "${var.service_name}-autoscale"
  location            = azurerm_resource_group.service.location
  resource_group_name = azurerm_resource_group.service.name
  target_resource_id  = azurerm_service_plan.service.id
  enabled             = true
  tags                = var.tags

  profile {
    name = "cpu-based-capacity"

    capacity {
      default = tostring(var.worker_count)
      minimum = tostring(var.worker_count)
      maximum = tostring(var.max_worker_count)
    }

    rule {
      metric_trigger {
        metric_name        = "CpuPercentage"
        metric_resource_id = azurerm_service_plan.service.id
        metric_namespace   = "Microsoft.Web/serverfarms"
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
        metric_resource_id = azurerm_service_plan.service.id
        metric_namespace   = "Microsoft.Web/serverfarms"
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT10M"
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

resource "azurerm_monitor_diagnostic_setting" "service" {
  name                       = "${var.service_name}-diagnostics"
  target_resource_id         = azurerm_linux_web_app.service.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.service.id

  enabled_log {
    category_group = "allLogs"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

resource "azurerm_monitor_diagnostic_setting" "staging" {
  name                       = "${var.service_name}-staging-diagnostics"
  target_resource_id         = azurerm_linux_web_app_slot.staging.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.service.id

  enabled_log {
    category_group = "allLogs"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}
