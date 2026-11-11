resource "azurerm_resource_group" "service" {
  name     = "rg-${var.name}"
  location = var.location
  tags     = var.tags
}

resource "azurerm_service_plan" "service" {
  name                = "asp-${var.name}"
  resource_group_name = azurerm_resource_group.service.name
  location            = azurerm_resource_group.service.location
  os_type             = "Linux"
  sku_name            = var.sku_name
  worker_count        = var.minimum_instances
  tags                = var.tags

  # Azure Monitor owns this value after initial provisioning.
  lifecycle {
    ignore_changes = [worker_count]
    precondition {
      condition     = var.maximum_instances >= var.minimum_instances
      error_message = "maximum_instances must be at least minimum_instances."
    }
  }
}

resource "azurerm_log_analytics_workspace" "service" {
  name                = "law-${var.name}"
  resource_group_name = azurerm_resource_group.service.name
  location            = azurerm_resource_group.service.location
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days
  tags                = var.tags
}

resource "azurerm_application_insights" "service" {
  name                = "appi-${var.name}"
  resource_group_name = azurerm_resource_group.service.name
  location            = azurerm_resource_group.service.location
  workspace_id        = azurerm_log_analytics_workspace.service.id
  application_type    = "web"
  tags                = var.tags
}

resource "azurerm_user_assigned_identity" "registry" {
  count               = var.acr_resource_id == null ? 0 : 1
  name                = "id-${var.name}-pull"
  resource_group_name = azurerm_resource_group.service.name
  location            = azurerm_resource_group.service.location
  tags                = var.tags
}

resource "azurerm_role_assignment" "registry_pull" {
  count                = var.acr_resource_id == null ? 0 : 1
  scope                = var.acr_resource_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.registry[0].principal_id
}

locals {
  platform_settings = {
    WEBSITES_PORT                         = tostring(var.container_port)
    APPLICATIONINSIGHTS_CONNECTION_STRING = azurerm_application_insights.service.connection_string
  }
  settings              = merge(var.app_settings, local.platform_settings)
  staging_settings      = merge(var.app_settings, var.staging_app_settings, local.platform_settings)
  registry_identity_ids = var.acr_resource_id == null ? null : [azurerm_user_assigned_identity.registry[0].id]
  registry_client_id    = var.acr_resource_id == null ? null : azurerm_user_assigned_identity.registry[0].client_id
}

resource "azurerm_linux_web_app" "service" {
  name                                           = var.name
  resource_group_name                            = azurerm_resource_group.service.name
  location                                       = azurerm_service_plan.service.location
  service_plan_id                                = azurerm_service_plan.service.id
  https_only                                     = true
  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = false
  app_settings                                   = local.settings
  tags                                           = var.tags

  identity {
    type         = var.acr_resource_id == null ? "SystemAssigned" : "SystemAssigned, UserAssigned"
    identity_ids = local.registry_identity_ids
  }

  dynamic "sticky_settings" {
    for_each = length(var.slot_sticky_setting_names) > 0 ? [1] : []
    content {
      app_setting_names = var.slot_sticky_setting_names
    }
  }

  site_config {
    always_on                                     = true
    ftps_state                                    = "Disabled"
    minimum_tls_version                           = "1.2"
    http2_enabled                                 = true
    health_check_path                             = var.health_check_path
    health_check_eviction_time_in_min             = 5
    container_registry_use_managed_identity       = var.acr_resource_id != null
    container_registry_managed_identity_client_id = local.registry_client_id
    application_stack {
      docker_image_name   = var.container_image
      docker_registry_url = var.container_registry_url
    }
  }
  depends_on = [azurerm_role_assignment.registry_pull]
}

resource "azurerm_linux_web_app_slot" "staging" {
  count                                          = var.enable_staging_slot ? 1 : 0
  name                                           = "staging"
  app_service_id                                 = azurerm_linux_web_app.service.id
  https_only                                     = true
  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = false
  app_settings                                   = local.staging_settings
  tags                                           = var.tags

  identity {
    type         = var.acr_resource_id == null ? "SystemAssigned" : "SystemAssigned, UserAssigned"
    identity_ids = local.registry_identity_ids
  }
  site_config {
    always_on                                     = true
    ftps_state                                    = "Disabled"
    minimum_tls_version                           = "1.2"
    http2_enabled                                 = true
    health_check_path                             = var.health_check_path
    health_check_eviction_time_in_min             = 5
    container_registry_use_managed_identity       = var.acr_resource_id != null
    container_registry_managed_identity_client_id = local.registry_client_id
    application_stack {
      docker_image_name   = coalesce(var.staging_container_image, var.container_image)
      docker_registry_url = var.container_registry_url
    }
  }
}

resource "azurerm_monitor_autoscale_setting" "service" {
  count               = var.enable_autoscale ? 1 : 0
  name                = "autoscale-${var.name}"
  resource_group_name = azurerm_resource_group.service.name
  location            = azurerm_resource_group.service.location
  target_resource_id  = azurerm_service_plan.service.id
  tags                = var.tags

  profile {
    name = "cpu"
    capacity {
      minimum = var.minimum_instances
      maximum = var.maximum_instances
      default = var.minimum_instances
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
        time_window        = "PT15M"
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

resource "azurerm_monitor_diagnostic_setting" "service" {
  name                       = "diag-${var.name}"
  target_resource_id         = azurerm_linux_web_app.service.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.service.id
  enabled_log { category = "AppServiceHTTPLogs" }
  enabled_log { category = "AppServiceConsoleLogs" }
  enabled_log { category = "AppServiceAppLogs" }
  enabled_log { category = "AppServicePlatformLogs" }
  enabled_metric { category = "AllMetrics" }
}

resource "azurerm_monitor_diagnostic_setting" "staging" {
  count                      = var.enable_staging_slot ? 1 : 0
  name                       = "diag-${var.name}-staging"
  target_resource_id         = azurerm_linux_web_app_slot.staging[0].id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.service.id
  enabled_log { category = "AppServiceHTTPLogs" }
  enabled_log { category = "AppServiceConsoleLogs" }
  enabled_log { category = "AppServiceAppLogs" }
  enabled_log { category = "AppServicePlatformLogs" }
  enabled_metric { category = "AllMetrics" }
}
