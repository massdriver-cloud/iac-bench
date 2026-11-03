locals {
  tags = merge(var.tags, { managed-by = "opentofu" })

  # Scale out quickly on sustained CPU, back in slowly.
  scale_rules = {
    out = { operator = "GreaterThan", threshold = 70, window = "PT5M", direction = "Increase", cooldown = "PT5M" }
    in  = { operator = "LessThan", threshold = 30, window = "PT10M", direction = "Decrease", cooldown = "PT10M" }
  }
}

# Capacity inputs are checked together before anything is planned.
resource "terraform_data" "capacity_guard" {
  lifecycle {
    precondition {
      condition     = var.max_instances >= var.min_instances
      error_message = "max_instances must be >= min_instances."
    }
  }
}

resource "azurerm_resource_group" "this" {
  name     = "rg-${var.name}"
  location = var.location
  tags     = local.tags
}

resource "azurerm_service_plan" "this" {
  name                   = "asp-${var.name}"
  resource_group_name    = azurerm_resource_group.this.name
  location               = azurerm_resource_group.this.location
  os_type                = "Linux"
  sku_name               = var.sku_name
  worker_count           = var.min_instances
  zone_balancing_enabled = var.zone_redundant
  tags                   = local.tags

  lifecycle {
    precondition {
      condition     = !var.zone_redundant || var.min_instances >= 3
      error_message = "zone_redundant requires min_instances >= 3."
    }
  }
}

resource "azurerm_monitor_autoscale_setting" "this" {
  name                = "autoscale-${var.name}"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  target_resource_id  = azurerm_service_plan.this.id
  tags                = local.tags

  profile {
    name = "cpu"

    capacity {
      default = var.min_instances
      minimum = var.min_instances
      maximum = var.max_instances
    }

    dynamic "rule" {
      for_each = local.scale_rules
      content {
        metric_trigger {
          metric_name        = "CpuPercentage"
          metric_resource_id = azurerm_service_plan.this.id
          time_grain         = "PT1M"
          statistic          = "Average"
          time_window        = rule.value.window
          time_aggregation   = "Average"
          operator           = rule.value.operator
          threshold          = rule.value.threshold
        }

        scale_action {
          direction = rule.value.direction
          type      = "ChangeCount"
          value     = "1"
          cooldown  = rule.value.cooldown
        }
      }
    }
  }
}

resource "azurerm_linux_web_app" "this" {
  name                = "app-${var.name}"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  service_plan_id     = azurerm_service_plan.this.id

  https_only                                     = true
  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = false

  identity {
    type = "SystemAssigned"
  }

  site_config {
    always_on                         = true
    minimum_tls_version               = "1.2"
    scm_minimum_tls_version           = "1.2"
    ftps_state                        = "Disabled"
    health_check_path                 = var.health_check_path
    health_check_eviction_time_in_min = 10

    application_stack {
      docker_image_name   = var.container_image
      docker_registry_url = var.registry_url
    }
  }

  app_settings = var.app_settings
  tags         = local.tags
}

# Releases deploy to the staging slot, warm up behind its health check, and
# swap into production; the previous release stays in the slot for rollback.
# The slot shares the plan, so it adds no capacity cost.
resource "azurerm_linux_web_app_slot" "staging" {
  name           = "staging"
  app_service_id = azurerm_linux_web_app.this.id

  https_only                                     = true
  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = false

  identity {
    type = "SystemAssigned"
  }

  site_config {
    always_on                         = true
    minimum_tls_version               = "1.2"
    scm_minimum_tls_version           = "1.2"
    ftps_state                        = "Disabled"
    health_check_path                 = var.health_check_path
    health_check_eviction_time_in_min = 10

    application_stack {
      docker_image_name   = var.container_image
      docker_registry_url = var.registry_url
    }
  }

  app_settings = var.app_settings
  tags         = local.tags
}

resource "azurerm_monitor_diagnostic_setting" "app" {
  count = var.log_analytics_workspace_id == null ? 0 : 1

  name                       = "diag-${var.name}"
  target_resource_id         = azurerm_linux_web_app.this.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category = "AppServiceHTTPLogs"
  }

  enabled_log {
    category = "AppServiceConsoleLogs"
  }

  enabled_log {
    category = "AppServicePlatformLogs"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}
