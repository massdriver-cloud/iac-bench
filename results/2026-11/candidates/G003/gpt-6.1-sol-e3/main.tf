locals {
  platform_settings = {
    WEBSITES_ENABLE_APP_SERVICE_STORAGE   = "false"
    WEBSITES_PORT                         = tostring(var.container.port)
    WEBSITE_SWAP_WARMUP_PING_PATH         = var.health_check_path
    WEBSITE_SWAP_WARMUP_PING_STATUSES     = "200"
    APPLICATIONINSIGHTS_CONNECTION_STRING = azurerm_application_insights.this.connection_string
  }
  settings = merge(var.app_settings, local.platform_settings)
}

resource "azurerm_resource_group" "this" {
  name     = "${var.name}-rg"
  location = var.location
  tags     = var.tags
}

resource "azurerm_service_plan" "this" {
  name                   = "${var.name}-plan"
  resource_group_name    = azurerm_resource_group.this.name
  location               = azurerm_resource_group.this.location
  os_type                = "Linux"
  sku_name               = var.capacity.sku
  worker_count           = var.capacity.default_instances
  zone_balancing_enabled = var.capacity.zone_redundant
  tags                   = var.tags

  # Azure Monitor owns this value after provisioning, including fixed-size mode.
  lifecycle {
    ignore_changes = [worker_count]
  }
}

resource "azurerm_linux_web_app" "this" {
  name                                           = var.name
  resource_group_name                            = azurerm_resource_group.this.name
  location                                       = azurerm_resource_group.this.location
  service_plan_id                                = azurerm_service_plan.this.id
  https_only                                     = true
  public_network_access_enabled                  = var.public_network_access_enabled
  virtual_network_subnet_id                      = var.integration_subnet_id
  vnet_image_pull_enabled                        = var.integration_subnet_id != null
  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = false
  client_affinity_enabled                        = false
  app_settings                                   = local.settings
  tags                                           = var.tags

  identity {
    type = "SystemAssigned"
  }

  site_config {
    always_on                               = true
    minimum_tls_version                     = "1.2"
    scm_minimum_tls_version                 = "1.2"
    ftps_state                              = "Disabled"
    http2_enabled                           = true
    health_check_path                       = var.health_check_path
    health_check_eviction_time_in_min       = 5
    container_registry_use_managed_identity = var.container.registry_resource_id != null
    vnet_route_all_enabled                  = var.integration_subnet_id != null
    scm_use_main_ip_restriction             = true
    ip_restriction_default_action           = length(var.allowed_inbound_cidrs) == 0 ? "Allow" : "Deny"

    application_stack {
      docker_image_name   = var.container.image
      docker_registry_url = var.container.registry_url
    }

    dynamic "ip_restriction" {
      for_each = { for index, cidr in var.allowed_inbound_cidrs : tostring(index) => cidr }
      content {
        name       = "allow-${ip_restriction.key}"
        priority   = 100 + tonumber(ip_restriction.key)
        action     = "Allow"
        ip_address = ip_restriction.value
      }
    }
  }

  sticky_settings {
    app_setting_names = distinct(concat(["APPLICATIONINSIGHTS_CONNECTION_STRING"], var.slot_sticky_setting_names))
  }

  logs {
    detailed_error_messages = false
    failed_request_tracing  = false
    application_logs {
      file_system_level = "Information"
    }
    http_logs {
      file_system {
        retention_in_days = 3
        retention_in_mb   = 35
      }
    }
  }
}

resource "azurerm_linux_web_app_slot" "staging" {
  count                                          = var.staging_enabled ? 1 : 0
  name                                           = "staging"
  app_service_id                                 = azurerm_linux_web_app.this.id
  https_only                                     = true
  public_network_access_enabled                  = var.public_network_access_enabled
  virtual_network_subnet_id                      = var.integration_subnet_id
  vnet_image_pull_enabled                        = var.integration_subnet_id != null
  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = false
  client_affinity_enabled                        = false
  app_settings                                   = local.settings
  tags                                           = var.tags

  identity {
    type = "SystemAssigned"
  }

  site_config {
    always_on                               = true
    minimum_tls_version                     = "1.2"
    scm_minimum_tls_version                 = "1.2"
    ftps_state                              = "Disabled"
    http2_enabled                           = true
    health_check_path                       = var.health_check_path
    health_check_eviction_time_in_min       = 5
    container_registry_use_managed_identity = var.container.registry_resource_id != null
    vnet_route_all_enabled                  = var.integration_subnet_id != null
    scm_use_main_ip_restriction             = true
    ip_restriction_default_action           = length(var.allowed_inbound_cidrs) == 0 ? "Allow" : "Deny"

    application_stack {
      docker_image_name   = coalesce(var.staging_image, var.container.image)
      docker_registry_url = var.container.registry_url
    }

    dynamic "ip_restriction" {
      for_each = { for index, cidr in var.allowed_inbound_cidrs : tostring(index) => cidr }
      content {
        name       = "allow-${ip_restriction.key}"
        priority   = 100 + tonumber(ip_restriction.key)
        action     = "Allow"
        ip_address = ip_restriction.value
      }
    }
  }

  logs {
    detailed_error_messages = false
    failed_request_tracing  = false
    application_logs {
      file_system_level = "Information"
    }
    http_logs {
      file_system {
        retention_in_days = 3
        retention_in_mb   = 35
      }
    }
  }
}

resource "azurerm_role_assignment" "production_pull" {
  count                = var.container.registry_resource_id != null ? 1 : 0
  scope                = var.container.registry_resource_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_linux_web_app.this.identity[0].principal_id
}

resource "azurerm_role_assignment" "staging_pull" {
  count                = var.container.registry_resource_id != null && var.staging_enabled ? 1 : 0
  scope                = var.container.registry_resource_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_linux_web_app_slot.staging[0].identity[0].principal_id
}
