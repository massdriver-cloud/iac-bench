locals {
  premium_v3_skus = ["P0v3", "P1v3", "P2v3", "P3v3", "P1mv3", "P2mv3", "P3mv3"]

  # Minimum instances the plan will run at. Zone redundancy needs at least 2.
  effective_min_instances = var.autoscale_enabled ? var.autoscale_min : var.instance_count

  # Module-managed settings take precedence over caller-supplied ones.
  app_settings = merge(var.app_settings, {
    WEBSITES_PORT                         = tostring(var.container_port)
    WEBSITES_ENABLE_APP_SERVICE_STORAGE   = "false"
    APPLICATIONINSIGHTS_CONNECTION_STRING = azurerm_application_insights.this.connection_string
  })

  use_registry_identity = var.container_registry_id != null
}

check "zone_redundancy_requires_premium_v3" {
  assert {
    condition     = !var.zone_redundant || contains(local.premium_v3_skus, var.service_plan_sku)
    error_message = "zone_redundant = true requires a Premium v3 SKU (P0v3, P1v3, P2v3, P3v3, P1mv3, P2mv3, P3mv3)."
  }
}

check "zone_redundancy_requires_two_instances" {
  assert {
    condition     = !var.zone_redundant || local.effective_min_instances >= 2
    error_message = "zone_redundant = true requires at least 2 instances (instance_count, or autoscale_min when autoscale is enabled)."
  }
}

check "autoscale_bounds" {
  assert {
    condition     = !var.autoscale_enabled || (var.autoscale_min <= var.autoscale_max && var.autoscale_scale_in_cpu_percent < var.autoscale_scale_out_cpu_percent)
    error_message = "With autoscale enabled, autoscale_min must be <= autoscale_max and autoscale_scale_in_cpu_percent must be below autoscale_scale_out_cpu_percent."
  }
}

resource "azurerm_resource_group" "this" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

resource "azurerm_service_plan" "this" {
  name                = "${var.name}-plan"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  os_type             = "Linux"
  sku_name            = var.service_plan_sku

  # When autoscale owns capacity, leave worker_count unset so Terraform does not fight it.
  worker_count = var.autoscale_enabled ? null : var.instance_count

  zone_balancing_enabled = var.zone_redundant

  tags = var.tags
}

resource "azurerm_linux_web_app" "this" {
  name                = var.name
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  service_plan_id     = azurerm_service_plan.this.id

  https_only                                     = true
  client_affinity_enabled                        = false
  public_network_access_enabled                  = true
  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = false

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
    container_registry_use_managed_identity = local.use_registry_identity

    application_stack {
      docker_image_name   = var.container_image
      docker_registry_url = var.container_registry_url
    }
  }

  app_settings = local.app_settings

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

  tags = var.tags
}

resource "azurerm_linux_web_app_slot" "staging" {
  count = var.staging_slot_enabled ? 1 : 0

  name           = "staging"
  app_service_id = azurerm_linux_web_app.this.id

  https_only                                     = true
  client_affinity_enabled                        = false
  public_network_access_enabled                  = true
  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = false

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
    container_registry_use_managed_identity = local.use_registry_identity

    application_stack {
      docker_image_name   = var.container_image
      docker_registry_url = var.container_registry_url
    }
  }

  app_settings = local.app_settings

  tags = var.tags
}

# Grant pull access to the app and slot identities when a registry is supplied.
resource "azurerm_role_assignment" "acr_pull_app" {
  count = local.use_registry_identity ? 1 : 0

  scope                = var.container_registry_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_linux_web_app.this.identity[0].principal_id
}

resource "azurerm_role_assignment" "acr_pull_staging" {
  count = local.use_registry_identity && var.staging_slot_enabled ? 1 : 0

  scope                = var.container_registry_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_linux_web_app_slot.staging[0].identity[0].principal_id
}

resource "azurerm_monitor_autoscale_setting" "this" {
  count = var.autoscale_enabled ? 1 : 0

  name                = "${var.name}-autoscale"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  target_resource_id  = azurerm_service_plan.this.id

  profile {
    name = "default"

    capacity {
      minimum = var.autoscale_min
      maximum = var.autoscale_max
      default = var.autoscale_min
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
        threshold          = var.autoscale_scale_out_cpu_percent
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
        threshold          = var.autoscale_scale_in_cpu_percent
      }

      scale_action {
        direction = "Decrease"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT10M"
      }
    }
  }

  tags = var.tags
}
