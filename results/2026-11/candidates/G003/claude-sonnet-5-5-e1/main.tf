resource "azurerm_resource_group" "this" {
  name     = var.resource_group_name
  location = var.location
  tags     = local.tags
}

locals {
  location = azurerm_resource_group.this.location
  rg       = azurerm_resource_group.this.name

  # Split "host/path:tag" into registry URL and image name.
  image_parts   = split("/", var.image)
  has_registry  = length(local.image_parts) > 1 && can(regex("[.:]|^localhost$", local.image_parts[0]))
  registry_url  = local.has_registry ? "https://${local.image_parts[0]}" : "https://index.docker.io"
  image_name    = local.has_registry ? join("/", slice(local.image_parts, 1, length(local.image_parts))) : var.image
  use_acr_mi    = var.acr_resource_id != null
  workspace_id  = var.log_analytics_workspace_id != null ? var.log_analytics_workspace_id : azurerm_log_analytics_workspace.this[0].id
  create_alerts = length(var.alert_action_group_ids) > 0

  app_settings = merge(
    {
      WEBSITES_PORT                       = tostring(var.container_port)
      WEBSITES_ENABLE_APP_SERVICE_STORAGE = "false"
      DOCKER_ENABLE_CI                    = "false"
    },
    var.app_settings,
    {
      APPLICATIONINSIGHTS_CONNECTION_STRING      = azurerm_application_insights.this.connection_string
      ApplicationInsightsAgent_EXTENSION_VERSION = "~3"
    },
  )

  tags = merge({ managed-by = "opentofu", service = var.name }, var.tags)

  alerts = local.create_alerts ? {
    http-5xx = {
      severity    = 2
      description = "HTTP 5xx responses above threshold."
      metric      = "Http5xx"
      aggregation = "Total"
      operator    = "GreaterThan"
      threshold   = var.alert_http_5xx_threshold
    }
    response-time = {
      severity    = 3
      description = "Average response time above threshold (seconds)."
      metric      = "HttpResponseTime"
      aggregation = "Average"
      operator    = "GreaterThan"
      threshold   = var.alert_response_time_seconds
    }
    health-check = {
      severity    = 1
      description = "Health check status below 100% (instances failing probes)."
      metric      = "HealthCheckStatus"
      aggregation = "Average"
      operator    = "LessThan"
      threshold   = 100
    }
  } : {}
}

# ---------------- Observability backbone ----------------

resource "azurerm_log_analytics_workspace" "this" {
  count               = var.log_analytics_workspace_id == null ? 1 : 0
  name                = "log-${var.name}"
  resource_group_name = local.rg
  location            = local.location
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days
  tags                = local.tags
}

resource "azurerm_application_insights" "this" {
  name                = "appi-${var.name}"
  resource_group_name = local.rg
  location            = local.location
  workspace_id        = local.workspace_id
  application_type    = "web"
  tags                = local.tags
}

# ---------------- Compute ----------------

resource "azurerm_service_plan" "this" {
  name                   = "asp-${var.name}"
  resource_group_name    = local.rg
  location               = local.location
  os_type                = "Linux"
  sku_name               = var.sku_name
  zone_balancing_enabled = var.zone_redundant
  worker_count           = var.min_instances
  tags                   = local.tags

  lifecycle {
    # Instance count is owned by autoscale after creation.
    ignore_changes = [worker_count]

    precondition {
      condition     = !var.zone_redundant || (can(regex("v3$", var.sku_name)) && var.min_instances >= 2)
      error_message = "zone_redundant requires a Premium v3 SKU and min_instances >= 2."
    }
    precondition {
      condition     = var.max_instances >= var.min_instances
      error_message = "max_instances must be >= min_instances."
    }
    precondition {
      condition     = var.scale_in_cpu_percent < var.scale_out_cpu_percent
      error_message = "scale_in_cpu_percent must be lower than scale_out_cpu_percent to avoid flapping."
    }
  }
}

resource "azurerm_linux_web_app" "this" {
  name                    = var.name
  resource_group_name     = local.rg
  location                = local.location
  service_plan_id         = azurerm_service_plan.this.id
  https_only              = true
  client_affinity_enabled = false
  app_settings            = local.app_settings
  tags                    = local.tags

  identity {
    type = "SystemAssigned"
  }

  site_config {
    always_on                               = true
    http2_enabled                           = true
    ftps_state                              = "Disabled"
    minimum_tls_version                     = "1.2"
    health_check_path                       = var.health_check_path
    health_check_eviction_time_in_min       = var.health_check_eviction_minutes
    container_registry_use_managed_identity = local.use_acr_mi
    load_balancing_mode                     = "LeastRequests"

    application_stack {
      docker_image_name   = local.image_name
      docker_registry_url = local.registry_url
    }
  }

  logs {
    detailed_error_messages = false
    failed_request_tracing  = false

    http_logs {
      file_system {
        retention_in_days = 3
        retention_in_mb   = 35
      }
    }
  }
}

# Roll out by changing var.image on the slot first, then swap
# (az webapp deployment slot swap). Re-apply afterwards with the new image
# so state and reality agree.
resource "azurerm_linux_web_app_slot" "staging" {
  count                   = var.enable_staging_slot ? 1 : 0
  name                    = "staging"
  app_service_id          = azurerm_linux_web_app.this.id
  https_only              = true
  client_affinity_enabled = false
  app_settings            = local.app_settings
  tags                    = local.tags

  identity {
    type = "SystemAssigned"
  }

  site_config {
    always_on                               = true
    http2_enabled                           = true
    ftps_state                              = "Disabled"
    minimum_tls_version                     = "1.2"
    health_check_path                       = var.health_check_path
    health_check_eviction_time_in_min       = var.health_check_eviction_minutes
    container_registry_use_managed_identity = local.use_acr_mi
    load_balancing_mode                     = "LeastRequests"

    application_stack {
      docker_image_name   = local.image_name
      docker_registry_url = local.registry_url
    }
  }
}

resource "azurerm_role_assignment" "acr_pull_app" {
  count                = local.use_acr_mi ? 1 : 0
  scope                = var.acr_resource_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_linux_web_app.this.identity[0].principal_id
}

resource "azurerm_role_assignment" "acr_pull_slot" {
  count                = local.use_acr_mi && var.enable_staging_slot ? 1 : 0
  scope                = var.acr_resource_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_linux_web_app_slot.staging[0].identity[0].principal_id
}

# ---------------- Autoscale ----------------

resource "azurerm_monitor_autoscale_setting" "this" {
  name                = "autoscale-${var.name}"
  resource_group_name = local.rg
  location            = local.location
  target_resource_id  = azurerm_service_plan.this.id
  tags                = local.tags

  profile {
    name = "default"

    capacity {
      default = var.min_instances
      minimum = var.min_instances
      maximum = var.max_instances
    }

    rule {
      metric_trigger {
        metric_name        = "CpuPercentage"
        metric_resource_id = azurerm_service_plan.this.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "GreaterThan"
        threshold          = var.scale_out_cpu_percent
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
        metric_name        = "MemoryPercentage"
        metric_resource_id = azurerm_service_plan.this.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "GreaterThan"
        threshold          = var.scale_out_memory_percent
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
        threshold          = var.scale_in_cpu_percent
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

# ---------------- Diagnostics ----------------

resource "azurerm_monitor_diagnostic_setting" "app" {
  name                       = "to-log-analytics"
  target_resource_id         = azurerm_linux_web_app.this.id
  log_analytics_workspace_id = local.workspace_id

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

# ---------------- Alerts ----------------

resource "azurerm_monitor_metric_alert" "this" {
  for_each            = local.alerts
  name                = "${var.name}-${each.key}"
  resource_group_name = local.rg
  scopes              = [azurerm_linux_web_app.this.id]
  description         = each.value.description
  severity            = each.value.severity
  frequency           = "PT1M"
  window_size         = "PT5M"
  tags                = local.tags

  criteria {
    metric_namespace = "Microsoft.Web/sites"
    metric_name      = each.value.metric
    aggregation      = each.value.aggregation
    operator         = each.value.operator
    threshold        = each.value.threshold
  }

  dynamic "action" {
    for_each = var.alert_action_group_ids
    content {
      action_group_id = action.value
    }
  }
}
