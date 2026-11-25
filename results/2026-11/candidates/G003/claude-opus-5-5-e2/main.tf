locals {
  create_rg           = var.resource_group_name == null
  resource_group_name = local.create_rg ? azurerm_resource_group.this[0].name : var.resource_group_name

  create_workspace = var.log_analytics_workspace_id == null
  workspace_id     = local.create_workspace ? azurerm_log_analytics_workspace.this[0].id : var.log_analytics_workspace_id

  use_acr       = var.container_registry_id != null
  staging_image = coalesce(var.staging_container_image, var.container_image)

  tags = merge(var.tags, { service = var.name, managed-by = "opentofu" })

  # Settings shared by production and the staging slot.
  base_app_settings = merge(
    var.app_settings,
    var.secret_app_settings,
    {
      WEBSITES_PORT                         = tostring(var.container_port)
      WEBSITES_ENABLE_APP_SERVICE_STORAGE   = "false"
      WEBSITES_CONTAINER_START_TIME_LIMIT   = "600"
      WEBSITE_SWAP_WARMUP_PING_PATH         = var.health_check_path
      WEBSITE_SWAP_WARMUP_PING_STATUSES     = "200"
      APPLICATIONINSIGHTS_CONNECTION_STRING = azurerm_application_insights.this.connection_string
    }
  )

  ip_restrictions = [
    for i, cidr in var.allowed_inbound_cidrs : {
      name     = "allow-${i}"
      cidr     = cidr
      priority = 100 + i
    }
  ]

  alert_actions = toset(var.alert_action_group_ids)
}

resource "azurerm_resource_group" "this" {
  count    = local.create_rg ? 1 : 0
  name     = "rg-${var.name}"
  location = var.location
  tags     = local.tags
}

# ---------------------------------------------------------------------------
# Observability
# ---------------------------------------------------------------------------

resource "azurerm_log_analytics_workspace" "this" {
  count               = local.create_workspace ? 1 : 0
  name                = "log-${var.name}"
  location            = var.location
  resource_group_name = local.resource_group_name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days
  tags                = local.tags
}

resource "azurerm_application_insights" "this" {
  name                = "appi-${var.name}"
  location            = var.location
  resource_group_name = local.resource_group_name
  workspace_id        = local.workspace_id
  application_type    = "web"
  tags                = local.tags
}

# ---------------------------------------------------------------------------
# Identity (registry pulls and Key Vault references)
# ---------------------------------------------------------------------------

resource "azurerm_user_assigned_identity" "this" {
  name                = "id-${var.name}"
  location            = var.location
  resource_group_name = local.resource_group_name
  tags                = local.tags
}

resource "azurerm_role_assignment" "acr_pull" {
  count                = local.use_acr ? 1 : 0
  scope                = var.container_registry_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.this.principal_id
  principal_type       = "ServicePrincipal"
}

# ---------------------------------------------------------------------------
# Compute
# ---------------------------------------------------------------------------

resource "azurerm_service_plan" "this" {
  name                   = "asp-${var.name}"
  location               = var.location
  resource_group_name    = local.resource_group_name
  os_type                = "Linux"
  sku_name               = var.sku_name
  worker_count           = var.min_instances
  zone_balancing_enabled = var.zone_redundant
  tags                   = local.tags

  lifecycle {
    # Autoscale owns the live instance count.
    ignore_changes = [worker_count]

    precondition {
      condition     = var.max_instances >= var.min_instances
      error_message = "max_instances must be >= min_instances."
    }
    precondition {
      condition     = !var.zone_redundant || (var.min_instances >= 2 && can(regex("^P[0-9]+m?v3$", var.sku_name)))
      error_message = "zone_redundant requires a Premium v3 sku_name (e.g. P1v3) and min_instances >= 2."
    }
  }
}

resource "azurerm_linux_web_app" "this" {
  name                                           = var.name
  location                                       = var.location
  resource_group_name                            = local.resource_group_name
  service_plan_id                                = azurerm_service_plan.this.id
  https_only                                     = true
  client_affinity_enabled                        = false
  public_network_access_enabled                  = true
  virtual_network_subnet_id                      = var.vnet_integration_subnet_id
  key_vault_reference_identity_id                = azurerm_user_assigned_identity.this.id
  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = false
  tags                                           = local.tags

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.this.id]
  }

  app_settings = local.base_app_settings

  site_config {
    always_on                                     = true
    http2_enabled                                 = true
    minimum_tls_version                           = "1.2"
    scm_minimum_tls_version                       = "1.2"
    ftps_state                                    = "Disabled"
    health_check_path                             = var.health_check_path
    health_check_eviction_time_in_min             = var.health_check_eviction_minutes
    vnet_route_all_enabled                        = var.vnet_integration_subnet_id != null
    container_registry_use_managed_identity       = local.use_acr
    container_registry_managed_identity_client_id = local.use_acr ? azurerm_user_assigned_identity.this.client_id : null
    ip_restriction_default_action                 = length(var.allowed_inbound_cidrs) > 0 ? "Deny" : "Allow"

    dynamic "ip_restriction" {
      for_each = local.ip_restrictions
      content {
        name       = ip_restriction.value.name
        ip_address = ip_restriction.value.cidr
        priority   = ip_restriction.value.priority
        action     = "Allow"
      }
    }

    application_stack {
      docker_image_name   = var.container_image
      docker_registry_url = var.container_registry_url
    }
  }

  logs {
    detailed_error_messages = true
    failed_request_tracing  = true

    application_logs {
      file_system_level = "Information"
    }

    http_logs {
      file_system {
        retention_in_days = 7
        retention_in_mb   = 35
      }
    }
  }

  depends_on = [azurerm_role_assignment.acr_pull]
}

resource "azurerm_linux_web_app_slot" "staging" {
  count                                          = var.staging_slot_enabled ? 1 : 0
  name                                           = "staging"
  app_service_id                                 = azurerm_linux_web_app.this.id
  https_only                                     = true
  client_affinity_enabled                        = false
  public_network_access_enabled                  = true
  virtual_network_subnet_id                      = var.vnet_integration_subnet_id
  key_vault_reference_identity_id                = azurerm_user_assigned_identity.this.id
  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = false
  tags                                           = local.tags

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.this.id]
  }

  app_settings = local.base_app_settings

  site_config {
    always_on                                     = true
    http2_enabled                                 = true
    minimum_tls_version                           = "1.2"
    scm_minimum_tls_version                       = "1.2"
    ftps_state                                    = "Disabled"
    health_check_path                             = var.health_check_path
    health_check_eviction_time_in_min             = var.health_check_eviction_minutes
    vnet_route_all_enabled                        = var.vnet_integration_subnet_id != null
    container_registry_use_managed_identity       = local.use_acr
    container_registry_managed_identity_client_id = local.use_acr ? azurerm_user_assigned_identity.this.client_id : null
    ip_restriction_default_action                 = length(var.allowed_inbound_cidrs) > 0 ? "Deny" : "Allow"

    dynamic "ip_restriction" {
      for_each = local.ip_restrictions
      content {
        name       = ip_restriction.value.name
        ip_address = ip_restriction.value.cidr
        priority   = ip_restriction.value.priority
        action     = "Allow"
      }
    }

    application_stack {
      docker_image_name   = local.staging_image
      docker_registry_url = var.container_registry_url
    }
  }

  logs {
    detailed_error_messages = true
    failed_request_tracing  = true

    application_logs {
      file_system_level = "Information"
    }

    http_logs {
      file_system {
        retention_in_days = 7
        retention_in_mb   = 35
      }
    }
  }

  depends_on = [azurerm_role_assignment.acr_pull]
}

# ---------------------------------------------------------------------------
# Autoscale
# ---------------------------------------------------------------------------

resource "azurerm_monitor_autoscale_setting" "this" {
  count               = var.autoscale_enabled ? 1 : 0
  name                = "autoscale-${var.name}"
  location            = var.location
  resource_group_name = local.resource_group_name
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

  lifecycle {
    precondition {
      condition     = var.scale_in_cpu_percent < var.scale_out_cpu_percent
      error_message = "scale_in_cpu_percent must be lower than scale_out_cpu_percent to avoid flapping."
    }
  }
}

# ---------------------------------------------------------------------------
# Diagnostics
# ---------------------------------------------------------------------------

resource "azurerm_monitor_diagnostic_setting" "app" {
  name                       = "diag-${var.name}"
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
  enabled_log {
    category = "AppServiceAuditLogs"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

resource "azurerm_monitor_diagnostic_setting" "plan" {
  name                       = "diag-${var.name}"
  target_resource_id         = azurerm_service_plan.this.id
  log_analytics_workspace_id = local.workspace_id

  enabled_metric {
    category = "AllMetrics"
  }
}

# ---------------------------------------------------------------------------
# Alerts
# ---------------------------------------------------------------------------

resource "azurerm_monitor_metric_alert" "http_5xx" {
  name                = "alert-${var.name}-http5xx"
  resource_group_name = local.resource_group_name
  scopes              = [azurerm_linux_web_app.this.id]
  description         = "HTTP 5xx responses exceeded ${var.alert_http_5xx_threshold} in 5 minutes."
  severity            = 1
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
    for_each = local.alert_actions
    content {
      action_group_id = action.value
    }
  }
}

resource "azurerm_monitor_metric_alert" "health" {
  name                = "alert-${var.name}-health"
  resource_group_name = local.resource_group_name
  scopes              = [azurerm_linux_web_app.this.id]
  description         = "One or more instances are failing the health check (${var.health_check_path})."
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
    for_each = local.alert_actions
    content {
      action_group_id = action.value
    }
  }
}

resource "azurerm_monitor_metric_alert" "response_time" {
  name                = "alert-${var.name}-latency"
  resource_group_name = local.resource_group_name
  scopes              = [azurerm_linux_web_app.this.id]
  description         = "Average response time exceeded ${var.alert_response_time_seconds}s over 5 minutes."
  severity            = 2
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
    for_each = local.alert_actions
    content {
      action_group_id = action.value
    }
  }
}

resource "azurerm_monitor_metric_alert" "plan_cpu_saturation" {
  name                = "alert-${var.name}-cpu"
  resource_group_name = local.resource_group_name
  scopes              = [azurerm_service_plan.this.id]
  description         = "Plan CPU above 90% for 15 minutes; autoscale may be capped at max_instances."
  severity            = 2
  frequency           = "PT5M"
  window_size         = "PT15M"
  tags                = local.tags

  criteria {
    metric_namespace = "Microsoft.Web/serverfarms"
    metric_name      = "CpuPercentage"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 90
  }

  dynamic "action" {
    for_each = local.alert_actions
    content {
      action_group_id = action.value
    }
  }
}
