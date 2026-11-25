locals {
  use_acr            = var.container.acr_id != null
  pull_acr_over_vnet = local.use_acr && var.integration_subnet_id != null
  platform_settings = {
    WEBSITES_PORT                         = tostring(var.container.port)
    WEBSITES_ENABLE_APP_SERVICE_STORAGE   = "false"
    WEBSITE_WARMUP_PATH                   = var.health_path
    WEBSITE_WARMUP_STATUSES               = "200"
    WEBSITE_SWAP_WARMUP_PING_PATH         = var.health_path
    WEBSITE_SWAP_WARMUP_PING_STATUSES     = "200"
    APPLICATIONINSIGHTS_CONNECTION_STRING = azurerm_application_insights.service.connection_string
  }
}

resource "azurerm_resource_group" "service" {
  name     = "rg-${var.name}"
  location = var.location
  tags     = var.tags
}

resource "azurerm_service_plan" "service" {
  name                   = var.name
  location               = azurerm_resource_group.service.location
  resource_group_name    = azurerm_resource_group.service.name
  os_type                = "Linux"
  sku_name               = var.capacity.sku
  worker_count           = var.capacity.minimum
  zone_balancing_enabled = var.capacity.zone_redundant
  tags                   = var.tags

  lifecycle {
    # Azure Monitor owns the live worker count after the plan is created.
    ignore_changes = [worker_count]
  }
}

resource "azurerm_user_assigned_identity" "pull" {
  count               = local.use_acr ? 1 : 0
  name                = "${var.name}-pull"
  resource_group_name = azurerm_resource_group.service.name
  location            = azurerm_resource_group.service.location
  tags                = var.tags
}

resource "azurerm_role_assignment" "pull" {
  count                            = local.use_acr ? 1 : 0
  scope                            = var.container.acr_id
  role_definition_name             = "AcrPull"
  principal_id                     = azurerm_user_assigned_identity.pull[0].principal_id
  skip_service_principal_aad_check = true
}

resource "azurerm_linux_web_app" "service" {
  name                                           = var.name
  location                                       = azurerm_resource_group.service.location
  resource_group_name                            = azurerm_resource_group.service.name
  service_plan_id                                = azurerm_service_plan.service.id
  https_only                                     = true
  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = false
  virtual_network_subnet_id                      = var.integration_subnet_id
  vnet_image_pull_enabled                        = local.pull_acr_over_vnet
  app_settings                                   = merge(var.app_settings, local.platform_settings)
  tags                                           = var.tags

  identity {
    type         = local.use_acr ? "SystemAssigned, UserAssigned" : "SystemAssigned"
    identity_ids = local.use_acr ? [azurerm_user_assigned_identity.pull[0].id] : null
  }

  site_config {
    always_on                                     = true
    ftps_state                                    = "Disabled"
    http2_enabled                                 = true
    minimum_tls_version                           = "1.2"
    scm_minimum_tls_version                       = "1.2"
    health_check_path                             = var.health_path
    health_check_eviction_time_in_min             = 2
    container_registry_use_managed_identity       = local.use_acr
    container_registry_managed_identity_client_id = local.use_acr ? azurerm_user_assigned_identity.pull[0].client_id : null

    application_stack {
      docker_image_name   = var.container.image
      docker_registry_url = var.container.registry_url
    }
  }

  dynamic "sticky_settings" {
    for_each = length(var.sticky_app_setting_names) > 0 ? [var.sticky_app_setting_names] : []
    content {
      app_setting_names = sort(tolist(sticky_settings.value))
    }
  }

  depends_on = [azurerm_role_assignment.pull]
}

resource "azurerm_linux_web_app_slot" "staging" {
  count                                          = var.staging == null ? 0 : 1
  name                                           = "staging"
  app_service_id                                 = azurerm_linux_web_app.service.id
  https_only                                     = true
  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = false
  virtual_network_subnet_id                      = var.integration_subnet_id
  vnet_image_pull_enabled                        = local.pull_acr_over_vnet
  app_settings                                   = merge(var.staging.app_settings, local.platform_settings)
  tags                                           = var.tags

  identity {
    type         = local.use_acr ? "SystemAssigned, UserAssigned" : "SystemAssigned"
    identity_ids = local.use_acr ? [azurerm_user_assigned_identity.pull[0].id] : null
  }

  site_config {
    always_on                                     = true
    ftps_state                                    = "Disabled"
    http2_enabled                                 = true
    minimum_tls_version                           = "1.2"
    scm_minimum_tls_version                       = "1.2"
    health_check_path                             = var.health_path
    health_check_eviction_time_in_min             = 2
    container_registry_use_managed_identity       = local.use_acr
    container_registry_managed_identity_client_id = local.use_acr ? azurerm_user_assigned_identity.pull[0].client_id : null
    ip_restriction_default_action                 = "Deny"
    scm_use_main_ip_restriction                   = true

    dynamic "ip_restriction" {
      for_each = sort(tolist(var.staging.allowed_cidrs))
      content {
        name       = "staging-client-${ip_restriction.key}"
        priority   = 100 + ip_restriction.key
        action     = "Allow"
        ip_address = ip_restriction.value
      }
    }

    application_stack {
      docker_image_name   = coalesce(var.staging.image, var.container.image)
      docker_registry_url = var.container.registry_url
    }
  }
}
