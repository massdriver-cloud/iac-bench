# ------------------------------------------------------------------------------
# App Service Plan (capacity + zones)
#
# Premium v3 / Isolated v2 SKUs carry the capacity posture the SRE team wants:
# private networking, multi-worker, and (where enabled) zone redundancy.
# ------------------------------------------------------------------------------

resource "azurerm_service_plan" "this" {
  name                = "asp-${local.app_name}"
  resource_group_name = var.resource_group_name
  location            = var.location

  os_type  = "Linux"
  sku_name = var.app_service_plan_sku_name

  worker_count = var.worker_count

  tags = local.common_tags
}

# ------------------------------------------------------------------------------
# Autoscale (capacity scaling)
#
# SREs set thresholds, not scale rules. We render CPU/memory target rules
# against the plan so capacity follows load out-of-band.
# ------------------------------------------------------------------------------

resource "azurerm_monitor_autoscale_setting" "this" {
  count = var.autoscale != null ? 1 : 0

  name                = "autoscale-${local.app_name}"
  resource_group_name = var.resource_group_name
  location            = var.location
  target_resource_id  = azurerm_service_plan.this.id

  profile {
    name = "default"
    capacity {
      default = var.autoscale.default_capacity
      minimum = var.autoscale.min_capacity
      maximum = var.autoscale.max_capacity
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
        threshold          = var.autoscale.cpu_target
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
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "LessThan"
        threshold          = var.autoscale.cpu_target / 3
      }
      scale_action {
        direction = "Decrease"
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
        threshold          = var.autoscale.memory_target
      }
      scale_action {
        direction = "Increase"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT5M"
      }
    }
  }
}

# ------------------------------------------------------------------------------
# Observability (diagnostic settings -> Log Analytics)
# ------------------------------------------------------------------------------

resource "azurerm_monitor_diagnostic_setting" "this" {
  count = var.log_analytics_workspace_id != null ? 1 : 0

  name                       = "diag-${local.app_name}"
  target_resource_id         = azurerm_linux_web_app.this.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

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

  metric {
    category = "AllMetrics"
  }
}

# ------------------------------------------------------------------------------
# Outputs
# ------------------------------------------------------------------------------

output "app_service_id" {
  description = "Resource ID of the App Service."
  value       = azurerm_linux_web_app.this.id
}

output "app_service_name" {
  description = "Name of the App Service."
  value       = azurerm_linux_web_app.this.name
}

output "default_hostname" {
  description = "Default hostname of the App Service."
  value       = azurerm_linux_web_app.this.default_hostname
}

output "service_plan_id" {
  description = "Resource ID of the App Service Plan."
  value       = azurerm_service_plan.this.id
}

output "staging_slot_default_hostname" {
  description = "Default hostname of the staging slot (empty if no slot)."
  value       = var.deployment_slot ? azurerm_linux_web_app_slot.staging[0].default_hostname : ""
}

output "identity_principal_id" {
  description = "Principal ID of the system-assigned managed identity."
  value       = azurerm_linux_web_app.this.identity[0].principal_id
}