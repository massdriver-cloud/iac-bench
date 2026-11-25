locals {
  resource_group_name = var.resource_group_name != null ? var.resource_group_name : azurerm_resource_group.this[0].name

  create_log_analytics       = var.log_analytics_workspace_id == null
  log_analytics_workspace_id = local.create_log_analytics ? azurerm_log_analytics_workspace.this[0].id : var.log_analytics_workspace_id

  use_acr_identity = var.container_registry_id != null

  # Settings the module owns. They win over user-supplied app_settings so that
  # observability and container plumbing cannot be accidentally overridden.
  platform_app_settings = {
    WEBSITES_PORT                         = tostring(var.container_port)
    WEBSITES_ENABLE_APP_SERVICE_STORAGE   = "false"
    WEBSITES_CONTAINER_START_TIME_LIMIT   = tostring(var.container_start_time_limit_seconds)
    DOCKER_ENABLE_CI                      = "false"
    APPLICATIONINSIGHTS_CONNECTION_STRING = azurerm_application_insights.this.connection_string
    APPINSIGHTS_INSTRUMENTATIONKEY        = azurerm_application_insights.this.instrumentation_key
  }

  app_settings = merge(var.app_settings, local.platform_app_settings)

  restrict_ingress = length(var.allowed_ip_ranges) > 0 || length(var.allowed_service_tags) > 0

  tags = merge(var.tags, {
    service    = var.name
    managed-by = "opentofu"
  })
}

########################################
# Resource group
########################################

resource "azurerm_resource_group" "this" {
  count = var.resource_group_name == null ? 1 : 0

  name     = "${var.name}-rg"
  location = var.location
  tags     = local.tags
}

########################################
# Identity (shared by the app and its slot so ACR pulls and Key Vault
# references keep working across swaps)
########################################

resource "azurerm_user_assigned_identity" "this" {
  name                = "${var.name}-id"
  location            = var.location
  resource_group_name = local.resource_group_name
  tags                = local.tags
}

resource "azurerm_role_assignment" "acr_pull" {
  count = local.use_acr_identity ? 1 : 0

  scope                = var.container_registry_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.this.principal_id
}

########################################
# Plan
########################################

resource "azurerm_service_plan" "this" {
  name                   = "${var.name}-plan"
  location               = var.location
  resource_group_name    = local.resource_group_name
  os_type                = "Linux"
  sku_name               = var.sku_name
  worker_count           = var.instance_count
  zone_balancing_enabled = var.zone_redundant
  tags                   = local.tags

  lifecycle {
    # When autoscale is on, the autoscale engine owns the live worker count.
    ignore_changes = [worker_count]
  }
}

########################################
# Web app (production)
########################################

resource "azurerm_linux_web_app" "this" {
  name                                           = var.name
  location                                       = var.location
  resource_group_name                            = local.resource_group_name
  service_plan_id                                = azurerm_service_plan.this.id
  https_only                                     = true
  client_affinity_enabled                        = false
  public_network_access_enabled                  = var.public_network_access_enabled
  virtual_network_subnet_id                      = var.vnet_integration_subnet_id
  key_vault_reference_identity_id                = azurerm_user_assigned_identity.this.id
  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = false
  tags                                           = local.tags

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.this.id]
  }

  app_settings = local.app_settings

  dynamic "sticky_settings" {
    for_each = length(var.sticky_app_setting_names) > 0 ? [1] : []
    content {
      app_setting_names = var.sticky_app_setting_names
    }
  }

  site_config {
    always_on                         = true
    http2_enabled                     = true
    minimum_tls_version               = "1.2"
    ftps_state                        = "Disabled"
    health_check_path                 = var.health_check_path
    health_check_eviction_time_in_min = var.health_check_eviction_time_in_min
    vnet_route_all_enabled            = var.vnet_integration_subnet_id != null
    ip_restriction_default_action     = local.restrict_ingress ? "Deny" : "Allow"

    container_registry_use_managed_identity       = local.use_acr_identity
    container_registry_managed_identity_client_id = local.use_acr_identity ? azurerm_user_assigned_identity.this.client_id : null

    application_stack {
      docker_image_name   = var.container_image
      docker_registry_url = var.container_registry_url
    }

    dynamic "ip_restriction" {
      for_each = var.allowed_ip_ranges
      content {
        name       = "allow-${replace(replace(ip_restriction.value, "/", "_"), ":", "-")}"
        action     = "Allow"
        priority   = 100 + index(var.allowed_ip_ranges, ip_restriction.value)
        ip_address = ip_restriction.value
      }
    }

    dynamic "ip_restriction" {
      for_each = var.allowed_service_tags
      content {
        name        = "allow-${ip_restriction.value}"
        action      = "Allow"
        priority    = 200 + index(var.allowed_service_tags, ip_restriction.value)
        service_tag = ip_restriction.value
      }
    }
  }

  logs {
    detailed_error_messages = true
    failed_request_tracing  = true

    application_logs {
      file_system_level = "Information"
    }

    http_logs {
      file_system {
        retention_in_days = 7
        retention_in_mb   = 100
      }
    }
  }

  depends_on = [azurerm_role_assignment.acr_pull]
}

########################################
# Staging slot (rollouts: deploy -> verify -> swap)
########################################

resource "azurerm_linux_web_app_slot" "staging" {
  count = var.staging_slot_enabled ? 1 : 0

  name                                           = "staging"
  app_service_id                                 = azurerm_linux_web_app.this.id
  https_only                                     = true
  client_affinity_enabled                        = false
  public_network_access_enabled                  = var.public_network_access_enabled
  virtual_network_subnet_id                      = var.vnet_integration_subnet_id
  key_vault_reference_identity_id                = azurerm_user_assigned_identity.this.id
  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = false
  tags                                           = local.tags

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.this.id]
  }

  app_settings = local.app_settings

  site_config {
    always_on                         = true
    http2_enabled                     = true
    minimum_tls_version               = "1.2"
    ftps_state                        = "Disabled"
    health_check_path                 = var.health_check_path
    health_check_eviction_time_in_min = var.health_check_eviction_time_in_min
    vnet_route_all_enabled            = var.vnet_integration_subnet_id != null
    ip_restriction_default_action     = local.restrict_ingress ? "Deny" : "Allow"

    container_registry_use_managed_identity       = local.use_acr_identity
    container_registry_managed_identity_client_id = local.use_acr_identity ? azurerm_user_assigned_identity.this.client_id : null

    application_stack {
      docker_image_name   = coalesce(var.staging_container_image, var.container_image)
      docker_registry_url = var.container_registry_url
    }

    dynamic "ip_restriction" {
      for_each = var.allowed_ip_ranges
      content {
        name       = "allow-${replace(replace(ip_restriction.value, "/", "_"), ":", "-")}"
        action     = "Allow"
        priority   = 100 + index(var.allowed_ip_ranges, ip_restriction.value)
        ip_address = ip_restriction.value
      }
    }

    dynamic "ip_restriction" {
      for_each = var.allowed_service_tags
      content {
        name        = "allow-${ip_restriction.value}"
        action      = "Allow"
        priority    = 200 + index(var.allowed_service_tags, ip_restriction.value)
        service_tag = ip_restriction.value
      }
    }
  }

  logs {
    detailed_error_messages = true
    failed_request_tracing  = true

    application_logs {
      file_system_level = "Information"
    }

    http_logs {
      file_system {
        retention_in_days = 7
        retention_in_mb   = 100
      }
    }
  }
}
