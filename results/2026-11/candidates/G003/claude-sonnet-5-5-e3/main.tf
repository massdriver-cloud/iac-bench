locals {
  resource_group_name = coalesce(var.resource_group_name, "rg-${var.name}")
  rg_name             = var.create_resource_group ? azurerm_resource_group.this[0].name : data.azurerm_resource_group.existing[0].name

  tags = merge({ service = var.name, managed-by = "opentofu" }, var.tags)

  staging_tag = coalesce(var.staging_container_image_tag, var.container_image_tag)

  base_app_settings = merge(
    {
      WEBSITES_PORT                              = tostring(var.container_port)
      WEBSITES_ENABLE_APP_SERVICE_STORAGE        = "false"
      APPLICATIONINSIGHTS_CONNECTION_STRING      = azurerm_application_insights.this.connection_string
      ApplicationInsightsAgent_EXTENSION_VERSION = "~3"
    },
    var.app_settings,
  )

  # Autoscale maximum can never be below the floor.
  max_instances = max(var.max_instances, var.min_instances)
}

resource "azurerm_resource_group" "this" {
  count    = var.create_resource_group ? 1 : 0
  name     = local.resource_group_name
  location = var.location
  tags     = local.tags
}

data "azurerm_resource_group" "existing" {
  count = var.create_resource_group ? 0 : 1
  name  = local.resource_group_name
}

############ Observability backbone ############

resource "azurerm_log_analytics_workspace" "this" {
  name                = "log-${var.name}"
  location            = var.location
  resource_group_name = local.rg_name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days
  tags                = local.tags
}

resource "azurerm_application_insights" "this" {
  name                = "appi-${var.name}"
  location            = var.location
  resource_group_name = local.rg_name
  workspace_id        = azurerm_log_analytics_workspace.this.id
  application_type    = "web"
  tags                = local.tags
}

############ Compute ############

resource "azurerm_service_plan" "this" {
  name                   = "asp-${var.name}"
  location               = var.location
  resource_group_name    = local.rg_name
  os_type                = "Linux"
  sku_name               = var.sku_name
  worker_count           = var.min_instances
  zone_balancing_enabled = var.zone_redundant
  tags                   = local.tags

  lifecycle {
    # Autoscale owns the instance count after creation.
    ignore_changes = [worker_count]
  }
}

resource "azurerm_linux_web_app" "this" {
  name                                           = var.name
  location                                       = var.location
  resource_group_name                            = local.rg_name
  service_plan_id                                = azurerm_service_plan.this.id
  https_only                                     = true
  public_network_access_enabled                  = true
  client_affinity_enabled                        = false
  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = false
  app_settings                                   = local.base_app_settings
  tags                                           = local.tags

  identity {
    type = "SystemAssigned"
  }

  site_config {
    always_on                               = true
    http2_enabled                           = true
    use_32_bit_worker                       = false
    ftps_state                              = "Disabled"
    minimum_tls_version                     = var.minimum_tls_version
    health_check_path                       = var.health_check_path
    health_check_eviction_time_in_min       = var.health_check_eviction_time_in_min
    container_registry_use_managed_identity = var.container_registry_use_managed_identity
    ip_restriction_default_action           = length(var.allowed_ip_ranges) > 0 ? "Deny" : "Allow"

    application_stack {
      docker_registry_url = var.container_registry_url
      docker_image_name   = "${var.container_image}:${var.container_image_tag}"
    }

    dynamic "ip_restriction" {
      for_each = var.allowed_ip_ranges
      content {
        name       = "allow-${ip_restriction.key}"
        priority   = 100 + ip_restriction.key
        action     = "Allow"
        ip_address = ip_restriction.value
      }
    }
  }

  logs {
    detailed_error_messages = true
    failed_request_tracing  = true

    http_logs {
      file_system {
        retention_in_days = 7
        retention_in_mb   = 35
      }
    }
  }
}

resource "azurerm_linux_web_app_slot" "staging" {
  count                                          = var.enable_staging_slot ? 1 : 0
  name                                           = "staging"
  app_service_id                                 = azurerm_linux_web_app.this.id
  https_only                                     = true
  client_affinity_enabled                        = false
  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = false
  app_settings                                   = local.base_app_settings
  tags                                           = local.tags

  identity {
    type = "SystemAssigned"
  }

  site_config {
    always_on                               = true
    http2_enabled                           = true
    use_32_bit_worker                       = false
    ftps_state                              = "Disabled"
    minimum_tls_version                     = var.minimum_tls_version
    health_check_path                       = var.health_check_path
    health_check_eviction_time_in_min       = var.health_check_eviction_time_in_min
    container_registry_use_managed_identity = var.container_registry_use_managed_identity
    ip_restriction_default_action           = length(var.allowed_ip_ranges) > 0 ? "Deny" : "Allow"

    application_stack {
      docker_registry_url = var.container_registry_url
      docker_image_name   = "${var.container_image}:${local.staging_tag}"
    }

    dynamic "ip_restriction" {
      for_each = var.allowed_ip_ranges
      content {
        name       = "allow-${ip_restriction.key}"
        priority   = 100 + ip_restriction.key
        action     = "Allow"
        ip_address = ip_restriction.value
      }
    }
  }
}

############ Autoscale ############

resource "azurerm_monitor_autoscale_setting" "this" {
  name                = "autoscale-${var.name}"
  location            = var.location
  resource_group_name = local.rg_name
  target_resource_id  = azurerm_service_plan.this.id
  tags                = local.tags

  profile {
    name = "cpu"

    capacity {
      default = var.min_instances
      minimum = var.min_instances
      maximum = local.max_instances
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
        threshold          = var.autoscale_cpu_scale_out_threshold
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
        time_window        = "PT10M"
        time_aggregation   = "Average"
        operator           = "LessThan"
        threshold          = var.autoscale_cpu_scale_in_threshold
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

############ Diagnostics ############

resource "azurerm_monitor_diagnostic_setting" "app" {
  name                       = "to-log-analytics"
  target_resource_id         = azurerm_linux_web_app.this.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id

  enabled_log {
    category = "AppServiceHTTPLogs"
  }
  enabled_log {
    category = "AppServiceConsoleLogs"
  }
  enabled_log {
    category = "AppServiceAppLogs"
  }
  enabled_log {
    category = "AppServicePlatformLogs"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

############ Alerting ############

resource "azurerm_monitor_action_group" "this" {
  count               = length(var.alert_email_addresses) > 0 ? 1 : 0
  name                = "ag-${var.name}"
  resource_group_name = local.rg_name
  short_name          = substr(replace(var.name, "-", ""), 0, 12)
  tags                = local.tags

  dynamic "email_receiver" {
    for_each = var.alert_email_addresses
    content {
      name                    = "sre-${email_receiver.key}"
      email_address           = email_receiver.value
      use_common_alert_schema = true
    }
  }
}

resource "azurerm_monitor_metric_alert" "http_5xx" {
  name                = "alert-${var.name}-http-5xx"
  resource_group_name = local.rg_name
  scopes              = [azurerm_linux_web_app.this.id]
  description         = "Elevated HTTP 5xx responses."
  severity            = 2
  frequency           = "PT1M"
  window_size         = "PT5M"
  tags                = local.tags

  criteria {
    metric_namespace = "Microsoft.Web/sites"
    metric_name      = "Http5xx"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = var.alert_http_5xx_threshold
  }

  dynamic "action" {
    for_each = azurerm_monitor_action_group.this
    content {
      action_group_id = action.value.id
    }
  }
}

resource "azurerm_monitor_metric_alert" "response_time" {
  name                = "alert-${var.name}-latency"
  resource_group_name = local.rg_name
  scopes              = [azurerm_linux_web_app.this.id]
  description         = "High average response time."
  severity            = 3
  frequency           = "PT1M"
  window_size         = "PT5M"
  tags                = local.tags

  criteria {
    metric_namespace = "Microsoft.Web/sites"
    metric_name      = "HttpResponseTime"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = var.alert_response_time_seconds
  }

  dynamic "action" {
    for_each = azurerm_monitor_action_group.this
    content {
      action_group_id = action.value.id
    }
  }
}

resource "azurerm_monitor_metric_alert" "health_check" {
  name                = "alert-${var.name}-health"
  resource_group_name = local.rg_name
  scopes              = [azurerm_linux_web_app.this.id]
  description         = "Instances are failing health checks (average health check status below 100%)."
  severity            = 1
  frequency           = "PT1M"
  window_size         = "PT5M"
  tags                = local.tags

  criteria {
    metric_namespace = "Microsoft.Web/sites"
    metric_name      = "HealthCheckStatus"
    aggregation      = "Average"
    operator         = "LessThan"
    threshold        = 100
  }

  dynamic "action" {
    for_each = azurerm_monitor_action_group.this
    content {
      action_group_id = action.value.id
    }
  }
}
