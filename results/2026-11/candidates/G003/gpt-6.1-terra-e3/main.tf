locals {
  settings = merge(var.app_settings, {
    WEBSITES_PORT                         = tostring(var.container_port)
    WEBSITES_ENABLE_APP_SERVICE_STORAGE   = "false"
    APPLICATIONINSIGHTS_CONNECTION_STRING = azurerm_application_insights.this.connection_string
  })
  staging_image = var.staging_container_image != null ? var.staging_container_image : var.container_image
}

resource "azurerm_service_plan" "this" {
  name                   = "${var.name}-plan"
  resource_group_name    = var.resource_group_name
  location               = var.location
  os_type                = "Linux"
  sku_name               = var.sku_name
  worker_count           = var.min_instances
  zone_balancing_enabled = var.zone_balancing_enabled
  tags                   = var.tags
  lifecycle {
    # Autoscale owns the live worker count after initial creation.
    ignore_changes = [worker_count]
    precondition {
      condition     = var.max_instances >= var.min_instances
      error_message = "max_instances must be at least min_instances."
    }
    precondition {
      condition     = !var.zone_balancing_enabled || var.min_instances >= 3
      error_message = "Zone balancing requires at least three instances."
    }
    precondition {
      condition     = (var.registry_username == null && var.registry_password == null) || (var.registry_username != null && var.registry_password != null && var.acr_resource_id == null)
      error_message = "Supply both registry_username and registry_password, or neither; credentials cannot be combined with acr_resource_id."
    }
  }
}

resource "azurerm_log_analytics_workspace" "this" {
  name                = "${var.name}-logs"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days
  tags                = var.tags
}

resource "azurerm_application_insights" "this" {
  name                = "${var.name}-insights"
  location            = var.location
  resource_group_name = var.resource_group_name
  workspace_id        = azurerm_log_analytics_workspace.this.id
  application_type    = "web"
  tags                = var.tags
}

resource "azurerm_linux_web_app" "this" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  service_plan_id     = azurerm_service_plan.this.id
  https_only          = true
  app_settings        = local.settings
  tags                = var.tags
  identity {
    type = "SystemAssigned"
  }
  site_config {
    always_on                               = true
    ftps_state                              = "Disabled"
    minimum_tls_version                     = "1.2"
    health_check_path                       = var.health_check_path
    health_check_eviction_time_in_min       = 5
    container_registry_use_managed_identity = var.acr_resource_id != null
    application_stack {
      docker_image_name        = var.container_image
      docker_registry_url      = var.container_registry_url
      docker_registry_username = var.registry_username
      docker_registry_password = var.registry_password
    }
  }
}

resource "azurerm_linux_web_app_slot" "staging" {
  count          = var.staging_slot_enabled ? 1 : 0
  name           = "staging"
  app_service_id = azurerm_linux_web_app.this.id
  https_only     = true
  app_settings   = local.settings
  tags           = var.tags
  identity {
    type = "SystemAssigned"
  }
  site_config {
    always_on                               = true
    ftps_state                              = "Disabled"
    minimum_tls_version                     = "1.2"
    health_check_path                       = var.health_check_path
    health_check_eviction_time_in_min       = 5
    container_registry_use_managed_identity = var.acr_resource_id != null
    application_stack {
      docker_image_name        = local.staging_image
      docker_registry_url      = var.container_registry_url
      docker_registry_username = var.registry_username
      docker_registry_password = var.registry_password
    }
  }
}

resource "azurerm_role_assignment" "app_acr_pull" {
  count                = var.acr_resource_id == null ? 0 : 1
  scope                = var.acr_resource_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_linux_web_app.this.identity[0].principal_id
}

resource "azurerm_role_assignment" "slot_acr_pull" {
  count                = var.acr_resource_id != null && var.staging_slot_enabled ? 1 : 0
  scope                = var.acr_resource_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_linux_web_app_slot.staging[0].identity[0].principal_id
}
