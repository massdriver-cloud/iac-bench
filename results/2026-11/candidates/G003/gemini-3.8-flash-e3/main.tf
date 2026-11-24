provider "azurerm" {
  features {}
}

locals {
  name_prefix_formatted = var.name_prefix != "" ? "${var.name_prefix}-" : ""
  base_name             = "${local.name_prefix_formatted}${var.service_name}-${var.environment}"
  app_name              = coalesce(var.custom_app_name, "app-${local.base_name}")
  service_plan_name     = coalesce(var.service_plan_name, "asp-${local.base_name}")

  service_plan_id = var.service_plan_id != null ? var.service_plan_id : azurerm_service_plan.plan[0].id

  default_app_settings = merge(
    {
      "WEBSITES_PORT"                       = tostring(var.container_port)
      "WEBSITES_ENABLE_APP_SERVICE_STORAGE" = "false"
      "DOCKER_ENABLE_CI"                    = tostring(var.docker_enable_ci)
    },
    var.enable_telemetry ? {
      "APPLICATIONINSIGHTS_CONNECTION_STRING"      = local.app_insights_connection_string
      "ApplicationInsightsAgent_EXTENSION_VERSION" = "~3"
      "XDT_MicrosoftApplicationInsights_Mode"      = "recommended"
    } : {}
  )

  app_settings = merge(local.default_app_settings, var.extra_app_settings)

  staging_app_settings = merge(
    local.app_settings,
    {
      "SLOT_NAME" = var.staging_slot_name
    },
    var.staging_extra_app_settings
  )
}

###############################################################################
# Capacity: App Service Plan (Dedicated Linux)
###############################################################################

resource "azurerm_service_plan" "plan" {
  count                  = var.service_plan_id == null ? 1 : 0
  name                   = local.service_plan_name
  resource_group_name    = var.resource_group_name
  location               = var.location
  os_type                = "Linux"
  sku_name               = var.sku_name
  worker_count           = var.capacity.default
  zone_balancing_enabled = var.zone_balancing_enabled
  tags                   = var.tags
}

###############################################################################
# Service: Production Linux Web App (Containerized HTTP API)
###############################################################################

resource "azurerm_linux_web_app" "app" {
  name                      = local.app_name
  resource_group_name       = var.resource_group_name
  location                  = var.location
  service_plan_id           = local.service_plan_id
  https_only                = true
  client_affinity_enabled   = false
  virtual_network_subnet_id = var.virtual_network_subnet_id

  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = false

  app_settings = local.app_settings

  identity {
    type         = var.identity_type
    identity_ids = contains(["UserAssigned", "SystemAssigned, UserAssigned"], var.identity_type) ? var.identity_ids : null
  }

  site_config {
    always_on                         = true
    ftps_state                        = "Disabled"
    minimum_tls_version               = var.minimum_tls_version
    http2_enabled                     = var.http2_enabled
    vnet_route_all_enabled            = var.virtual_network_subnet_id != null ? true : false
    health_check_path                 = var.health_check_path
    health_check_eviction_time_in_min = var.health_check_eviction_time_in_min

    container_registry_use_managed_identity = var.container_registry_use_managed_identity

    application_stack {
      docker_image_name        = var.container_image
      docker_registry_url      = var.container_registry_url
      docker_registry_username = var.container_registry_username
      docker_registry_password = var.container_registry_password
    }

    dynamic "ip_restriction" {
      for_each = var.ip_restrictions
      content {
        name                      = ip_restriction.value.name
        ip_address                = ip_restriction.value.ip_address
        service_tag               = ip_restriction.value.service_tag
        virtual_network_subnet_id = ip_restriction.value.virtual_network_subnet_id
        priority                  = ip_restriction.value.priority
        action                    = ip_restriction.value.action
        description               = ip_restriction.value.description
      }
    }

    dynamic "scm_ip_restriction" {
      for_each = var.scm_ip_restrictions
      content {
        name                      = scm_ip_restriction.value.name
        ip_address                = scm_ip_restriction.value.ip_address
        service_tag               = scm_ip_restriction.value.service_tag
        virtual_network_subnet_id = scm_ip_restriction.value.virtual_network_subnet_id
        priority                  = scm_ip_restriction.value.priority
        action                    = scm_ip_restriction.value.action
        description               = scm_ip_restriction.value.description
      }
    }
  }

  dynamic "sticky_settings" {
    for_each = var.enable_staging_slot ? [1] : []
    content {
      app_setting_names = distinct(concat(["SLOT_NAME"], var.sticky_app_setting_names))
    }
  }

  tags = var.tags
}

###############################################################################
# Rollouts: Staging Deployment Slot (Zero-Downtime Blue/Green)
###############################################################################

resource "azurerm_linux_web_app_slot" "staging" {
  count                     = var.enable_staging_slot ? 1 : 0
  name                      = var.staging_slot_name
  app_service_id            = azurerm_linux_web_app.app.id
  https_only                = true
  client_affinity_enabled   = false
  virtual_network_subnet_id = var.virtual_network_subnet_id

  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = false

  app_settings = local.staging_app_settings

  identity {
    type         = var.identity_type
    identity_ids = contains(["UserAssigned", "SystemAssigned, UserAssigned"], var.identity_type) ? var.identity_ids : null
  }

  site_config {
    always_on                         = true
    ftps_state                        = "Disabled"
    minimum_tls_version               = var.minimum_tls_version
    http2_enabled                     = var.http2_enabled
    vnet_route_all_enabled            = var.virtual_network_subnet_id != null ? true : false
    health_check_path                 = var.health_check_path
    health_check_eviction_time_in_min = var.health_check_eviction_time_in_min
    auto_swap_slot_name               = var.auto_swap_slot_name

    container_registry_use_managed_identity = var.container_registry_use_managed_identity

    application_stack {
      docker_image_name        = var.container_image
      docker_registry_url      = var.container_registry_url
      docker_registry_username = var.container_registry_username
      docker_registry_password = var.container_registry_password
    }

    dynamic "ip_restriction" {
      for_each = var.ip_restrictions
      content {
        name                      = ip_restriction.value.name
        ip_address                = ip_restriction.value.ip_address
        service_tag               = ip_restriction.value.service_tag
        virtual_network_subnet_id = ip_restriction.value.virtual_network_subnet_id
        priority                  = ip_restriction.value.priority
        action                    = ip_restriction.value.action
        description               = ip_restriction.value.description
      }
    }

    dynamic "scm_ip_restriction" {
      for_each = var.scm_ip_restrictions
      content {
        name                      = scm_ip_restriction.value.name
        ip_address                = scm_ip_restriction.value.ip_address
        service_tag               = scm_ip_restriction.value.service_tag
        virtual_network_subnet_id = scm_ip_restriction.value.virtual_network_subnet_id
        priority                  = scm_ip_restriction.value.priority
        action                    = scm_ip_restriction.value.action
        description               = scm_ip_restriction.value.description
      }
    }
  }

  tags = var.tags
}
