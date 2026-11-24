locals {
  base_name = "${var.name}-${var.environment}"

  tags = merge(
    {
      service     = var.name
      environment = var.environment
      managed-by  = "opentofu"
    },
    var.tags,
  )

  create_rg           = var.resource_group_name == null
  resource_group_name = local.create_rg ? azurerm_resource_group.this[0].name : var.resource_group_name

  create_workspace = var.log_analytics_workspace_id == null
  workspace_id     = local.create_workspace ? azurerm_log_analytics_workspace.this[0].id : var.log_analytics_workspace_id

  use_acr = var.acr_id != null

  # Settings the platform needs; user settings may not override them.
  platform_app_settings = {
    WEBSITES_PORT                         = tostring(var.container_port)
    WEBSITES_ENABLE_APP_SERVICE_STORAGE   = "false"
    WEBSITES_CONTAINER_START_TIME_LIMIT   = "600"
    APPLICATIONINSIGHTS_CONNECTION_STRING = azurerm_application_insights.this.connection_string
    # Slot swaps only complete once the staging instances answer the health path.
    WEBSITE_SWAP_WARMUP_PING_PATH     = var.health_check_path
    WEBSITE_SWAP_WARMUP_PING_STATUSES = "200,202,204"
  }

  app_settings = merge(var.app_settings, local.platform_app_settings)

  site_logs = {
    detailed_error_messages = true
    failed_request_tracing  = false
    http_logs_retention_mb  = 35
    http_logs_retention_d   = 3
  }
}

############################################
# Resource group
############################################

resource "azurerm_resource_group" "this" {
  count    = local.create_rg ? 1 : 0
  name     = "rg-${local.base_name}"
  location = var.location
  tags     = local.tags
}

############################################
# Observability backends
############################################

resource "azurerm_log_analytics_workspace" "this" {
  count               = local.create_workspace ? 1 : 0
  name                = "log-${local.base_name}"
  location            = var.location
  resource_group_name = local.resource_group_name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days
  tags                = local.tags
}

resource "azurerm_application_insights" "this" {
  name                = "appi-${local.base_name}"
  location            = var.location
  resource_group_name = local.resource_group_name
  workspace_id        = local.workspace_id
  application_type    = "web"
  tags                = local.tags
}

############################################
# Compute
############################################

resource "azurerm_service_plan" "this" {
  name                   = "asp-${local.base_name}"
  location               = var.location
  resource_group_name    = local.resource_group_name
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
      condition     = !var.zone_redundant || (can(regex("v3$", var.sku_name)) && var.min_instances >= 2)
      error_message = "zone_redundant requires a Premium v3 SKU and min_instances >= 2."
    }
    precondition {
      condition     = var.scale_in_cpu_percent < var.scale_out_cpu_percent
      error_message = "scale_in_cpu_percent must be lower than scale_out_cpu_percent to avoid flapping."
    }
    # Autoscale owns the live instance count.
    ignore_changes = [worker_count]
  }
}

resource "azurerm_linux_web_app" "this" {
  name                                           = "app-${local.base_name}"
  location                                       = var.location
  resource_group_name                            = local.resource_group_name
  service_plan_id                                = azurerm_service_plan.this.id
  https_only                                     = true
  client_affinity_enabled                        = false
  public_network_access_enabled                  = true
  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = false
  app_settings                                   = local.app_settings
  tags                                           = local.tags

  identity {
    type = "SystemAssigned"
  }

  site_config {
    always_on                               = true
    http2_enabled                           = true
    minimum_tls_version                     = "1.2"
    scm_minimum_tls_version                 = "1.2"
    ftps_state                              = "Disabled"
    health_check_path                       = var.health_check_path
    health_check_eviction_time_in_min       = var.health_check_eviction_minutes
    container_registry_use_managed_identity = local.use_acr

    application_stack {
      docker_image_name   = var.container_image
      docker_registry_url = var.container_registry_url
    }
  }

  logs {
    detailed_error_messages = local.site_logs.detailed_error_messages
    failed_request_tracing  = local.site_logs.failed_request_tracing

    http_logs {
      file_system {
        retention_in_mb   = local.site_logs.http_logs_retention_mb
        retention_in_days = local.site_logs.http_logs_retention_d
      }
    }
  }

  dynamic "sticky_settings" {
    for_each = length(var.slot_sticky_app_settings) > 0 ? [1] : []
    content {
      app_setting_names = var.slot_sticky_app_settings
    }
  }

  lifecycle {
    # Image rollouts happen via staging slot deploy + swap, outside Terraform.
    ignore_changes = [
      site_config[0].application_stack[0].docker_image_name,
    ]
  }
}

resource "azurerm_linux_web_app_slot" "staging" {
  count                                          = var.enable_staging_slot ? 1 : 0
  name                                           = "staging"
  app_service_id                                 = azurerm_linux_web_app.this.id
  https_only                                     = true
  client_affinity_enabled                        = false
  public_network_access_enabled                  = true
  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = false
  app_settings                                   = local.app_settings
  tags                                           = local.tags

  identity {
    type = "SystemAssigned"
  }

  site_config {
    always_on                               = true
    http2_enabled                           = true
    minimum_tls_version                     = "1.2"
    scm_minimum_tls_version                 = "1.2"
    ftps_state                              = "Disabled"
    health_check_path                       = var.health_check_path
    health_check_eviction_time_in_min       = var.health_check_eviction_minutes
    container_registry_use_managed_identity = local.use_acr

    application_stack {
      docker_image_name   = var.container_image
      docker_registry_url = var.container_registry_url
    }
  }

  logs {
    detailed_error_messages = local.site_logs.detailed_error_messages
    failed_request_tracing  = local.site_logs.failed_request_tracing

    http_logs {
      file_system {
        retention_in_mb   = local.site_logs.http_logs_retention_mb
        retention_in_days = local.site_logs.http_logs_retention_d
      }
    }
  }

  lifecycle {
    ignore_changes = [
      site_config[0].application_stack[0].docker_image_name,
    ]
  }
}

############################################
# Registry access (managed identity, no registry passwords)
############################################

resource "azurerm_role_assignment" "acr_pull_app" {
  count                = local.use_acr ? 1 : 0
  scope                = var.acr_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_linux_web_app.this.identity[0].principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "acr_pull_slot" {
  count                = local.use_acr && var.enable_staging_slot ? 1 : 0
  scope                = var.acr_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_linux_web_app_slot.staging[0].identity[0].principal_id
  principal_type       = "ServicePrincipal"
}

############################################
# Autoscale
############################################

resource "azurerm_monitor_autoscale_setting" "this" {
  name                = "autoscale-${local.base_name}"
  location            = var.location
  resource_group_name = local.resource_group_name
  target_resource_id  = azurerm_service_plan.this.id
  enabled             = var.max_instances > var.min_instances
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
        time_window        = "PT10M"
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
        time_window        = "PT10M"
        time_aggregation   = "Average"
        operator           = "GreaterThan"
        threshold          = 80
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
