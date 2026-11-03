terraform {
  required_version = ">= 1.6.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.0.0, < 5.0.0"
    }
  }
}

provider "azurerm" {
  features {}

  # When null, AzureRM reads the subscription from its standard environment
  # variables / Azure CLI authentication context.
  subscription_id = var.subscription_id
}

resource "azurerm_resource_group" "service" {
  name     = "${var.app_name}-rg"
  location = var.location
  tags     = local.tags
}

resource "azurerm_log_analytics_workspace" "service" {
  name                = "${var.app_name}-law"
  location            = azurerm_resource_group.service.location
  resource_group_name = azurerm_resource_group.service.name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days
  daily_quota_gb      = var.log_daily_quota_gb
  tags                = local.tags
}

resource "azurerm_application_insights" "service" {
  name                = "${var.app_name}-appi"
  location            = azurerm_resource_group.service.location
  resource_group_name = azurerm_resource_group.service.name
  workspace_id        = azurerm_log_analytics_workspace.service.id
  application_type    = "web"
  tags                = local.tags
}

resource "azurerm_service_plan" "service" {
  name                   = "${var.app_name}-plan"
  location               = azurerm_resource_group.service.location
  resource_group_name    = azurerm_resource_group.service.name
  os_type                = "Linux"
  sku_name               = var.sku_name
  worker_count           = var.worker_count
  zone_balancing_enabled = var.zone_redundant
  tags                   = local.tags

  # Autoscale owns the live worker count after initial provisioning.
  lifecycle {
    ignore_changes = [worker_count]
  }
}

resource "azurerm_linux_web_app" "service" {
  name                                           = var.app_name
  location                                       = azurerm_resource_group.service.location
  resource_group_name                            = azurerm_resource_group.service.name
  service_plan_id                                = azurerm_service_plan.service.id
  https_only                                     = true
  public_network_access_enabled                  = true
  virtual_network_subnet_id                      = var.integration_subnet_id
  client_affinity_enabled                        = false
  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = false

  identity {
    type = "SystemAssigned"
  }

  site_config {
    always_on                         = true
    http2_enabled                     = true
    ftps_state                        = "Disabled"
    minimum_tls_version               = "1.2"
    health_check_path                 = var.health_check_path
    health_check_eviction_time_in_min = 5

    application_stack {
      docker_image_name        = var.container_image
      docker_registry_url      = var.container_registry_url
      docker_registry_username = var.container_registry_username
      docker_registry_password = var.container_registry_password
    }
  }

  app_settings = merge(
    {
      WEBSITES_PORT                         = tostring(var.container_port)
      APPLICATIONINSIGHTS_CONNECTION_STRING = azurerm_application_insights.service.connection_string
      APPLICATIONINSIGHTS_ENABLE_AGENT      = "true"
      WEBSITE_HEALTHCHECK_MAXPINGFAILURES   = "10"
    },
    var.app_settings
  )

  logs {
    application_logs {
      file_system_level = "Information"
    }
    detailed_error_messages = true
    failed_request_tracing  = true
  }

  tags = local.tags
}

resource "azurerm_monitor_autoscale_setting" "service" {
  count               = var.enable_autoscale ? 1 : 0
  name                = "${var.app_name}-autoscale"
  location            = azurerm_resource_group.service.location
  resource_group_name = azurerm_resource_group.service.name
  target_resource_id  = azurerm_service_plan.service.id
  enabled             = true
  tags                = local.tags

  profile {
    name = "cpu-based-capacity"

    capacity {
      default = tostring(var.worker_count)
      minimum = tostring(var.autoscale_min_workers)
      maximum = tostring(var.autoscale_max_workers)
    }

    rule {
      metric_trigger {
        metric_name        = "CpuPercentage"
        metric_resource_id = azurerm_service_plan.service.id
        metric_namespace   = "Microsoft.Web/serverfarms"
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "GreaterThan"
        threshold          = var.scale_out_cpu_threshold
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
        metric_namespace   = "Microsoft.Web/serverfarms"
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT10M"
        time_aggregation   = "Average"
        operator           = "LessThan"
        threshold          = var.scale_in_cpu_threshold
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

locals {
  tags = merge(
    {
      managed_by = "opentofu"
      service    = var.app_name
    },
    var.tags
  )
}
