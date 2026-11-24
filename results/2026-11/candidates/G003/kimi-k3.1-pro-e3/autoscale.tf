resource "azurerm_monitor_autoscale_setting" "this" {
  count = var.autoscale_enabled ? 1 : 0

  name                = "${var.name}-autoscale"
  resource_group_name = local.resource_group_name
  location            = local.resource_group_location
  target_resource_id  = local.service_plan_id
  enabled             = true
  tags                = local.tags

  profile {
    name = "default"

    capacity {
      default = var.autoscale_default_capacity
      minimum = var.autoscale_minimum_capacity
      maximum = var.autoscale_maximum_capacity
    }

    # Scale out on either CPU or memory pressure. Either signal can indicate
    # saturation for the mix of containers sharing the plan.
    rule {
      metric_trigger {
        metric_name        = "CpuPercentage"
        metric_namespace   = "Microsoft.Web/serverfarms"
        metric_resource_id = local.service_plan_id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
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
        metric_name        = "MemoryPercentage"
        metric_namespace   = "Microsoft.Web/serverfarms"
        metric_resource_id = local.service_plan_id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "GreaterThan"
        threshold          = var.autoscale_memory_scale_out_threshold
      }

      scale_action {
        direction = "Increase"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT5M"
      }
    }

    # Azure requires all scale-in rules to match. Requiring both CPU and memory
    # to be cool prevents a single quiet signal from removing needed capacity.
    rule {
      metric_trigger {
        metric_name        = "CpuPercentage"
        metric_namespace   = "Microsoft.Web/serverfarms"
        metric_resource_id = local.service_plan_id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "LessThan"
        threshold          = var.autoscale_cpu_scale_in_threshold
      }

      scale_action {
        direction = "Decrease"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT15M"
      }
    }

    rule {
      metric_trigger {
        metric_name        = "MemoryPercentage"
        metric_namespace   = "Microsoft.Web/serverfarms"
        metric_resource_id = local.service_plan_id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "LessThan"
        threshold          = var.autoscale_memory_scale_in_threshold
      }

      scale_action {
        direction = "Decrease"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT15M"
      }
    }
  }

  dynamic "notification" {
    for_each = length(var.autoscale_notification_emails) > 0 ? [1] : []
    content {
      email {
        custom_emails = var.autoscale_notification_emails
      }
    }
  }
}
