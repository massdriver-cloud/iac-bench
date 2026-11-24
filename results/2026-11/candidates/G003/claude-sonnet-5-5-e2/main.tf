locals {
  rg_name     = coalesce(var.resource_group_name, "rg-${var.name}")
  rg_location = var.create_resource_group ? azurerm_resource_group.this[0].location : data.azurerm_resource_group.existing[0].location
  rg_ref      = var.create_resource_group ? azurerm_resource_group.this[0].name : data.azurerm_resource_group.existing[0].name

  tags = merge(
    {
      service     = var.name
      environment = var.environment
      managed_by  = "opentofu"
    },
    var.tags,
  )

  use_acr_identity = var.acr_resource_id != null

  base_app_settings = merge(
    {
      WEBSITES_PORT                              = tostring(var.container_port)
      WEBSITES_ENABLE_APP_SERVICE_STORAGE        = "false"
      APPLICATIONINSIGHTS_CONNECTION_STRING      = azurerm_application_insights.this.connection_string
      ApplicationInsightsAgent_EXTENSION_VERSION = "~3"
    },
    var.app_settings,
  )
}

resource "azurerm_resource_group" "this" {
  count    = var.create_resource_group ? 1 : 0
  name     = local.rg_name
  location = var.location
  tags     = local.tags
}

data "azurerm_resource_group" "existing" {
  count = var.create_resource_group ? 0 : 1
  name  = local.rg_name
}

# ---------- Capacity ----------

resource "azurerm_service_plan" "this" {
  name                   = "asp-${var.name}"
  resource_group_name    = local.rg_ref
  location               = local.rg_location
  os_type                = "Linux"
  sku_name               = var.sku_name
  worker_count           = var.min_instances
  zone_balancing_enabled = var.zone_redundant
  tags                   = local.tags

  lifecycle {
    precondition {
      condition     = var.max_instances >= var.min_instances
      error_message = "max_instances must be >= min_instances."
    }
    precondition {
      condition     = !var.zone_redundant || var.min_instances >= 2
      error_message = "zone_redundant requires min_instances >= 2."
    }
    precondition {
      condition     = !var.zone_redundant || !can(regex("^S", var.sku_name))
      error_message = "zone_redundant requires a Premium v2/v3 or Isolated v2 SKU."
    }
    precondition {
      condition     = var.autoscale_cpu_scale_in_threshold < var.autoscale_cpu_scale_out_threshold
      error_message = "Scale-in CPU threshold must be lower than scale-out threshold."
    }
  }
}

resource "azurerm_monitor_autoscale_setting" "this" {
  name                = "autoscale-${var.name}"
  resource_group_name = local.rg_ref
  location            = local.rg_location
  target_resource_id  = azurerm_service_plan.this.id
  tags                = local.tags

  profile {
    name = "cpu"

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
        time_window        = "PT15M"
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

# ---------- Observability backends ----------

resource "azurerm_log_analytics_workspace" "this" {
  name                = "log-${var.name}"
  resource_group_name = local.rg_ref
  location            = local.rg_location
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days
  tags                = local.tags
}

resource "azurerm_application_insights" "this" {
  name                = "appi-${var.name}"
  resource_group_name = local.rg_ref
  location            = local.rg_location
  workspace_id        = azurerm_log_analytics_workspace.this.id
  application_type    = "web"
  tags                = local.tags
}

# ---------- Web app ----------

resource "azurerm_linux_web_app" "this" {
  name                          = var.name
  resource_group_name           = local.rg_ref
  location                      = local.rg_location
  service_plan_id               = azurerm_service_plan.this.id
  https_only                    = true
  public_network_access_enabled = var.public_network_access_enabled
  virtual_network_subnet_id     = var.subnet_id
  client_affinity_enabled       = false
  app_settings                  = local.base_app_settings
  tags                          = local.tags

  identity {
    type = "SystemAssigned"
  }

  site_config {
    always_on                               = true
    http2_enabled                           = true
    ftps_state                              = "Disabled"
    minimum_tls_version                     = "1.2"
    health_check_path                       = var.health_check_path
    health_check_eviction_time_in_min       = var.health_check_eviction_time_in_min
    container_registry_use_managed_identity = local.use_acr_identity
    vnet_route_all_enabled                  = var.subnet_id != null
    ip_restriction_default_action           = length(var.ip_restriction_allowed_cidrs) > 0 ? "Deny" : "Allow"

    application_stack {
      docker_image_name   = "${var.container_image}:${var.container_image_tag}"
      docker_registry_url = var.container_registry_url
    }

    dynamic "ip_restriction" {
      for_each = var.ip_restriction_allowed_cidrs
      content {
        name       = "allow-${ip_restriction.key}"
        action     = "Allow"
        ip_address = ip_restriction.value
        priority   = 100 + ip_restriction.key
      }
    }
  }

  logs {
    detailed_error_messages = true
    failed_request_tracing  = true

    http_logs {
      file_system {
        retention_in_days = 3
        retention_in_mb   = 35
      }
    }
  }

  lifecycle {
    # Image tag is rolled out by the deployment pipeline (slot swap); don't revert it on apply.
    ignore_changes = [
      site_config[0].application_stack[0].docker_image_name,
    ]
  }
}

resource "azurerm_linux_web_app_slot" "staging" {
  count                         = var.enable_staging_slot ? 1 : 0
  name                          = "staging"
  app_service_id                = azurerm_linux_web_app.this.id
  https_only                    = true
  public_network_access_enabled = var.public_network_access_enabled
  virtual_network_subnet_id     = var.subnet_id
  client_affinity_enabled       = false
  app_settings                  = local.base_app_settings
  tags                          = local.tags

  identity {
    type = "SystemAssigned"
  }

  site_config {
    always_on                               = true
    http2_enabled                           = true
    ftps_state                              = "Disabled"
    minimum_tls_version                     = "1.2"
    health_check_path                       = var.health_check_path
    health_check_eviction_time_in_min       = var.health_check_eviction_time_in_min
    container_registry_use_managed_identity = local.use_acr_identity
    vnet_route_all_enabled                  = var.subnet_id != null
    ip_restriction_default_action           = length(var.ip_restriction_allowed_cidrs) > 0 ? "Deny" : "Allow"

    application_stack {
      docker_image_name   = "${var.container_image}:${var.container_image_tag}"
      docker_registry_url = var.container_registry_url
    }

    dynamic "ip_restriction" {
      for_each = var.ip_restriction_allowed_cidrs
      content {
        name       = "allow-${ip_restriction.key}"
        action     = "Allow"
        ip_address = ip_restriction.value
        priority   = 100 + ip_restriction.key
      }
    }
  }

  lifecycle {
    ignore_changes = [
      site_config[0].application_stack[0].docker_image_name,
    ]
  }
}

resource "azurerm_role_assignment" "acr_pull" {
  count                = local.use_acr_identity ? 1 : 0
  scope                = var.acr_resource_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_linux_web_app.this.identity[0].principal_id
}

resource "azurerm_role_assignment" "acr_pull_staging" {
  count                = local.use_acr_identity && var.enable_staging_slot ? 1 : 0
  scope                = var.acr_resource_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_linux_web_app_slot.staging[0].identity[0].principal_id
}

resource "azurerm_monitor_diagnostic_setting" "app" {
  name                       = "diag-${var.name}"
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

# ---------- Alerting ----------

resource "azurerm_monitor_action_group" "this" {
  count               = length(var.alert_email_addresses) > 0 ? 1 : 0
  name                = "ag-${var.name}"
  resource_group_name = local.rg_ref
  short_name          = substr(replace(var.name, "-", ""), 0, 12)
  tags                = local.tags

  dynamic "email_receiver" {
    for_each = var.alert_email_addresses
    content {
      name                    = "email-${email_receiver.key}"
      email_address           = email_receiver.value
      use_common_alert_schema = true
    }
  }
}

resource "azurerm_monitor_metric_alert" "http_5xx" {
  name                = "alert-${var.name}-5xx"
  resource_group_name = local.rg_ref
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
  resource_group_name = local.rg_ref
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
  resource_group_name = local.rg_ref
  scopes              = [azurerm_linux_web_app.this.id]
  description         = "Instances failing health checks."
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
