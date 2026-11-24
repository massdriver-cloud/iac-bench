locals {
  tags = merge(var.tags, { "managed-by" = "opentofu" })

  runtime_settings = {
    WEBSITES_PORT                         = tostring(var.container_port)
    WEBSITES_ENABLE_APP_SERVICE_STORAGE   = "false"
    WEBSITES_CONTAINER_START_TIME_LIMIT   = "300"
    WEBSITE_WARMUP_PATH                   = var.health_check_path
    WEBSITE_WARMUP_STATUSES               = "200"
    WEBSITE_SWAP_WARMUP_PING_PATH         = var.health_check_path
    WEBSITE_SWAP_WARMUP_PING_STATUSES     = "200"
    APPLICATIONINSIGHTS_CONNECTION_STRING = azurerm_application_insights.this.connection_string
  }
  # Only setting NAMES are declassified; values remain sensitive.
  sticky_setting_names = sort(distinct(concat(
    nonsensitive(keys(var.app_settings)),
    nonsensitive(keys(var.staging_app_settings)),
    keys(local.runtime_settings)
  )))
  scale_rules = var.capacity.autoscale_enabled ? {
    out = { operator = "GreaterThan", threshold = var.capacity.scale_out_cpu, window = "PT5M", direction = "Increase", cooldown = "PT5M" }
    in  = { operator = "LessThan", threshold = var.capacity.scale_in_cpu, window = "PT15M", direction = "Decrease", cooldown = "PT10M" }
  } : {}
}

resource "azurerm_resource_group" "this" {
  name     = "rg-${var.name}"
  location = var.location
  tags     = local.tags
}

resource "azurerm_user_assigned_identity" "app" {
  name                = "id-${var.name}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.tags
}

resource "azurerm_role_assignment" "acr_pull" {
  count                = var.registry.resource_id == null ? 0 : 1
  scope                = var.registry.resource_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.app.principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_service_plan" "this" {
  name                   = "asp-${var.name}"
  location               = azurerm_resource_group.this.location
  resource_group_name    = azurerm_resource_group.this.name
  os_type                = "Linux"
  sku_name               = var.sku_name
  worker_count           = var.capacity.minimum
  zone_balancing_enabled = var.zone_redundant
  tags                   = local.tags

  lifecycle {
    # Azure Monitor owns worker count after creation, including fixed capacity.
    ignore_changes = [worker_count]
    precondition {
      condition     = !var.zone_redundant || var.capacity.minimum >= 2
      error_message = "Zone redundancy requires at least two minimum workers and a supported region."
    }
  }
}

resource "azurerm_monitor_autoscale_setting" "this" {
  name                = "scale-${var.name}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  target_resource_id  = azurerm_service_plan.this.id
  enabled             = true
  tags                = local.tags

  profile {
    name = "standard"
    capacity {
      default = tostring(var.capacity.minimum)
      minimum = tostring(var.capacity.minimum)
      maximum = tostring(var.capacity.autoscale_enabled ? var.capacity.maximum : var.capacity.minimum)
    }
    dynamic "rule" {
      for_each = local.scale_rules
      content {
        metric_trigger {
          metric_name        = "CpuPercentage"
          metric_namespace   = "Microsoft.Web/serverfarms"
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
  name                                           = var.name
  location                                       = azurerm_resource_group.this.location
  resource_group_name                            = azurerm_resource_group.this.name
  service_plan_id                                = azurerm_service_plan.this.id
  https_only                                     = true
  public_network_access_enabled                  = true
  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = false
  client_affinity_enabled                        = false
  virtual_network_subnet_id                      = var.integration_subnet_id
  vnet_image_pull_enabled                        = var.integration_subnet_id != null
  key_vault_reference_identity_id                = azurerm_user_assigned_identity.app.id
  app_settings                                   = merge(var.app_settings, local.runtime_settings)
  tags                                           = local.tags

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.app.id]
  }

  site_config {
    always_on                                     = true
    use_32_bit_worker                             = false
    minimum_tls_version                           = "1.2"
    scm_minimum_tls_version                       = "1.2"
    ftps_state                                    = "Disabled"
    http2_enabled                                 = true
    app_command_line                              = var.startup_command
    health_check_path                             = var.health_check_path
    health_check_eviction_time_in_min             = 5
    container_registry_use_managed_identity       = var.registry.resource_id != null
    container_registry_managed_identity_client_id = var.registry.resource_id == null ? null : azurerm_user_assigned_identity.app.client_id
    vnet_route_all_enabled                        = var.integration_subnet_id != null && var.vnet_route_all_enabled
    scm_use_main_ip_restriction                   = true
    ip_restriction_default_action                 = length(var.allowed_ip_cidrs) == 0 ? "Allow" : "Deny"

    application_stack {
      docker_image_name   = var.container_image
      docker_registry_url = var.registry.server_url
    }
    dynamic "ip_restriction" {
      for_each = var.allowed_ip_cidrs
      content {
        name       = "allow-${ip_restriction.key}"
        priority   = 100 + ip_restriction.key
        action     = "Allow"
        ip_address = ip_restriction.value
      }
    }
  }

  sticky_settings {
    app_setting_names = local.sticky_setting_names
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

  depends_on = [azurerm_role_assignment.acr_pull]
}

resource "azurerm_linux_web_app_slot" "staging" {
  count                                          = var.staging.enabled ? 1 : 0
  name                                           = "staging"
  app_service_id                                 = azurerm_linux_web_app.this.id
  https_only                                     = true
  public_network_access_enabled                  = true
  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = false
  client_affinity_enabled                        = false
  virtual_network_subnet_id                      = var.integration_subnet_id
  vnet_image_pull_enabled                        = var.integration_subnet_id != null
  key_vault_reference_identity_id                = azurerm_user_assigned_identity.app.id
  app_settings                                   = merge(var.app_settings, var.staging_app_settings, local.runtime_settings)
  tags                                           = local.tags

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.app.id]
  }

  site_config {
    always_on                                     = true
    use_32_bit_worker                             = false
    minimum_tls_version                           = "1.2"
    scm_minimum_tls_version                       = "1.2"
    ftps_state                                    = "Disabled"
    http2_enabled                                 = true
    app_command_line                              = var.startup_command
    health_check_path                             = var.health_check_path
    health_check_eviction_time_in_min             = 5
    container_registry_use_managed_identity       = var.registry.resource_id != null
    container_registry_managed_identity_client_id = var.registry.resource_id == null ? null : azurerm_user_assigned_identity.app.client_id
    vnet_route_all_enabled                        = var.integration_subnet_id != null && var.vnet_route_all_enabled
    scm_use_main_ip_restriction                   = true
    ip_restriction_default_action                 = length(var.allowed_ip_cidrs) == 0 ? "Allow" : "Deny"

    application_stack {
      docker_image_name   = coalesce(var.staging.container_image, var.container_image)
      docker_registry_url = var.registry.server_url
    }
    dynamic "ip_restriction" {
      for_each = var.allowed_ip_cidrs
      content {
        name       = "allow-${ip_restriction.key}"
        priority   = 100 + ip_restriction.key
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
