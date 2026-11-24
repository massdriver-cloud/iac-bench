locals {
  settings = merge(var.app_settings, {
    WEBSITES_PORT                       = tostring(var.container_port)
    WEBSITES_ENABLE_APP_SERVICE_STORAGE = "false"
    WEBSITE_WARMUP_PATH                 = var.health_path
    WEBSITE_WARMUP_STATUSES             = "200"
    WEBSITE_SWAP_WARMUP_PING_PATH       = var.health_path
    WEBSITE_SWAP_WARMUP_PING_STATUSES   = "200"
  })
}
resource "azurerm_resource_group" "service" {
  name     = "${var.app_name}-rg"
  location = var.location
  tags     = var.tags
}
resource "azurerm_service_plan" "service" {
  name                   = "${var.app_name}-plan"
  resource_group_name    = azurerm_resource_group.service.name
  location               = azurerm_resource_group.service.location
  os_type                = "Linux"
  sku_name               = var.capacity.sku
  worker_count           = var.capacity.workers
  zone_balancing_enabled = var.capacity.zone_redundant
  tags                   = var.tags
}
resource "azurerm_user_assigned_identity" "pull" {
  count               = var.acr_id == null ? 0 : 1
  name                = "${var.app_name}-pull"
  location            = azurerm_resource_group.service.location
  resource_group_name = azurerm_resource_group.service.name
  tags                = var.tags
}
resource "azurerm_role_assignment" "pull" {
  count                = var.acr_id == null ? 0 : 1
  scope                = var.acr_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.pull[0].principal_id
  principal_type       = "ServicePrincipal"
}
resource "azurerm_linux_web_app" "service" {
  name                                           = var.app_name
  location                                       = azurerm_resource_group.service.location
  resource_group_name                            = azurerm_resource_group.service.name
  service_plan_id                                = azurerm_service_plan.service.id
  https_only                                     = true
  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = false
  client_affinity_enabled                        = false
  app_settings                                   = local.settings
  tags                                           = var.tags
  depends_on                                     = [azurerm_role_assignment.pull]
  identity {
    type         = var.acr_id == null ? "SystemAssigned" : "SystemAssigned, UserAssigned"
    identity_ids = azurerm_user_assigned_identity.pull[*].id
  }
  site_config {
    always_on                                     = true
    http2_enabled                                 = true
    ftps_state                                    = "Disabled"
    minimum_tls_version                           = "1.2"
    scm_minimum_tls_version                       = "1.2"
    health_check_path                             = var.health_path
    health_check_eviction_time_in_min             = 5
    container_registry_use_managed_identity       = var.acr_id != null
    container_registry_managed_identity_client_id = one(azurerm_user_assigned_identity.pull[*].client_id)
    application_stack {
      docker_image_name   = var.image
      docker_registry_url = var.registry_url
    }
  }
  logs {
    application_logs { file_system_level = "Information" }
    http_logs {
      file_system {
        retention_in_days = 3
        retention_in_mb   = 35
      }
    }
  }
}
resource "azurerm_linux_web_app_slot" "staging" {
  count                                          = var.staging_image == null ? 0 : 1
  name                                           = "staging"
  app_service_id                                 = azurerm_linux_web_app.service.id
  https_only                                     = true
  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = false
  client_affinity_enabled                        = false
  app_settings                                   = local.settings
  tags                                           = var.tags
  identity {
    type         = var.acr_id == null ? "SystemAssigned" : "SystemAssigned, UserAssigned"
    identity_ids = azurerm_user_assigned_identity.pull[*].id
  }
  site_config {
    always_on                                     = true
    http2_enabled                                 = true
    ftps_state                                    = "Disabled"
    minimum_tls_version                           = "1.2"
    scm_minimum_tls_version                       = "1.2"
    health_check_path                             = var.health_path
    health_check_eviction_time_in_min             = 5
    container_registry_use_managed_identity       = var.acr_id != null
    container_registry_managed_identity_client_id = one(azurerm_user_assigned_identity.pull[*].client_id)
    application_stack {
      docker_image_name   = var.staging_image
      docker_registry_url = var.registry_url
    }
  }
  logs {
    application_logs { file_system_level = "Information" }
    http_logs {
      file_system {
        retention_in_days = 3
        retention_in_mb   = 35
      }
    }
  }
}
