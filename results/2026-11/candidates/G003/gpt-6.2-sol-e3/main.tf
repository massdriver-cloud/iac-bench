locals {
  sku_names = {
    small  = "P1v3"
    medium = "P2v3"
    large  = "P3v3"
  }

  registry_url = var.acr == null ? var.public_registry_url : "https://${var.acr.login_server}"

  # These are the module-owned settings for the single-container App Service model.
  platform_settings = {
    WEBSITES_PORT                       = tostring(var.container_port)
    WEBSITES_ENABLE_APP_SERVICE_STORAGE = "false"
    WEBSITES_CONTAINER_START_TIME_LIMIT = "300"
    WEBSITE_WARMUP_PATH                 = var.health_check_path
    WEBSITE_WARMUP_STATUSES             = "200,204"
    WEBSITE_SWAP_WARMUP_PING_PATH       = var.health_check_path
    WEBSITE_SWAP_WARMUP_PING_STATUSES   = "200,204"
  }

  sticky_setting_names = sort(tolist(setsubtract(toset(keys(var.staging_app_settings)), toset(keys(local.platform_settings)))))
}

resource "azurerm_resource_group" "service" {
  name     = "${var.name}-rg"
  location = var.location
  tags     = var.tags
}

resource "azurerm_service_plan" "service" {
  name                   = "${var.name}-plan"
  resource_group_name    = azurerm_resource_group.service.name
  location               = azurerm_resource_group.service.location
  os_type                = "Linux"
  sku_name               = local.sku_names[var.capacity.size]
  worker_count           = var.capacity.minimum
  zone_balancing_enabled = var.capacity.zone_redundant
  tags                   = var.tags

  lifecycle {
    # Azure Monitor owns the live count after creation. Bounds are managed below.
    ignore_changes = [worker_count]
  }
}

resource "azurerm_user_assigned_identity" "registry" {
  count = var.acr == null ? 0 : 1

  name                = "${var.name}-pull"
  resource_group_name = azurerm_resource_group.service.name
  location            = azurerm_resource_group.service.location
  tags                = var.tags
}

resource "azurerm_role_assignment" "registry_pull" {
  count = var.acr == null ? 0 : 1

  scope                            = var.acr.id
  role_definition_name             = "AcrPull"
  principal_id                     = azurerm_user_assigned_identity.registry[0].principal_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}

resource "azurerm_linux_web_app" "production" {
  name                                           = var.name
  resource_group_name                            = azurerm_resource_group.service.name
  location                                       = azurerm_resource_group.service.location
  service_plan_id                                = azurerm_service_plan.service.id
  https_only                                     = true
  public_network_access_enabled                  = true
  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = false
  app_settings                                   = merge(var.app_settings, local.platform_settings)
  tags                                           = var.tags

  identity {
    type         = var.acr == null ? "SystemAssigned" : "SystemAssigned, UserAssigned"
    identity_ids = azurerm_user_assigned_identity.registry[*].id
  }

  site_config {
    always_on                                     = true
    http2_enabled                                 = true
    ftps_state                                    = "Disabled"
    minimum_tls_version                           = "1.2"
    scm_minimum_tls_version                       = "1.2"
    scm_use_main_ip_restriction                   = false
    scm_ip_restriction_default_action             = "Deny"
    health_check_path                             = var.health_check_path
    health_check_eviction_time_in_min             = 5
    container_registry_use_managed_identity       = var.acr != null
    container_registry_managed_identity_client_id = one(azurerm_user_assigned_identity.registry[*].client_id)

    application_stack {
      docker_image_name   = var.container_image
      docker_registry_url = local.registry_url
    }
  }

  dynamic "sticky_settings" {
    for_each = var.create_staging_slot && length(local.sticky_setting_names) > 0 ? [local.sticky_setting_names] : []
    content {
      app_setting_names = sticky_settings.value
    }
  }

  depends_on = [azurerm_role_assignment.registry_pull]
}

resource "azurerm_linux_web_app_slot" "staging" {
  count = var.create_staging_slot ? 1 : 0

  name                                           = "staging"
  app_service_id                                 = azurerm_linux_web_app.production.id
  https_only                                     = true
  public_network_access_enabled                  = true
  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = false
  app_settings                                   = merge(var.app_settings, var.staging_app_settings, local.platform_settings)
  tags                                           = var.tags

  identity {
    type         = var.acr == null ? "SystemAssigned" : "SystemAssigned, UserAssigned"
    identity_ids = azurerm_user_assigned_identity.registry[*].id
  }

  site_config {
    always_on                                     = true
    http2_enabled                                 = true
    ftps_state                                    = "Disabled"
    minimum_tls_version                           = "1.2"
    scm_minimum_tls_version                       = "1.2"
    scm_use_main_ip_restriction                   = false
    scm_ip_restriction_default_action             = "Deny"
    ip_restriction_default_action                 = "Deny"
    health_check_path                             = var.health_check_path
    health_check_eviction_time_in_min             = 5
    container_registry_use_managed_identity       = var.acr != null
    container_registry_managed_identity_client_id = one(azurerm_user_assigned_identity.registry[*].client_id)

    dynamic "ip_restriction" {
      for_each = sort(tolist(var.staging_allowed_cidrs))
      content {
        name       = "reviewer-${ip_restriction.key + 1}"
        priority   = 100 + ip_restriction.key
        action     = "Allow"
        ip_address = ip_restriction.value
      }
    }

    application_stack {
      docker_image_name   = coalesce(var.staging_image, var.container_image)
      docker_registry_url = local.registry_url
    }
  }
}

resource "azurerm_monitor_autoscale_setting" "service" {
  name                = "${var.name}-autoscale"
  resource_group_name = azurerm_resource_group.service.name
  location            = azurerm_resource_group.service.location
  target_resource_id  = azurerm_service_plan.service.id
  enabled             = true
  tags                = var.tags

  profile {
    name = "steady-state"

    capacity {
      minimum = var.capacity.minimum
      default = var.capacity.minimum
      maximum = var.capacity.maximum
    }

    rule {
      metric_trigger {
        metric_name        = "CpuPercentage"
        metric_namespace   = "Microsoft.Web/serverfarms"
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
        value     = 1
        cooldown  = "PT5M"
      }
    }

    rule {
      metric_trigger {
        metric_name        = "CpuPercentage"
        metric_namespace   = "Microsoft.Web/serverfarms"
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
        value     = 1
        cooldown  = "PT10M"
      }
    }
  }
}
