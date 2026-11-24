locals {
  environments = toset(var.enable_staging_slot ? ["production", "staging"] : ["production"])
  acr          = var.acr_id != null
  # The provider expects a fully qualified image name, without the URL scheme.
  image_name = "${trimprefix(var.image.registry_url, "https://")}/${var.image.repository}"

  platform_settings = {
    WEBSITES_PORT                       = tostring(var.container_port)
    WEBSITES_ENABLE_APP_SERVICE_STORAGE = "false"
    WEBSITE_WARMUP_PATH                 = var.health_check_path
    WEBSITE_WARMUP_STATUSES             = "200"
    WEBSITE_SWAP_WARMUP_PING_PATH       = var.health_check_path
    WEBSITE_SWAP_WARMUP_PING_STATUSES   = "200"
  }

  reserved_settings = toset(concat(keys(local.platform_settings), [
    "APPLICATIONINSIGHTS_CONNECTION_STRING", "WEBSITE_HEALTHCHECK_MAXPINGFAILURES",
    "WEBSITE_OVERRIDE_PRESERVE_DEFAULT_STICKY_SLOT_SETTINGS",
    "DOCKER_CUSTOM_IMAGE_NAME", "DOCKER_REGISTRY_SERVER_URL",
    "DOCKER_REGISTRY_SERVER_USERNAME", "DOCKER_REGISTRY_SERVER_PASSWORD"
  ]))

  app_settings = {
    for env in local.environments : env => merge(
      var.app_settings,
      { for key, values in var.environment_settings : key => values[env] },
      local.platform_settings,
      { APPLICATIONINSIGHTS_CONNECTION_STRING = azurerm_application_insights.app[env].connection_string }
    )
  }
}

resource "azurerm_resource_group" "service" {
  name     = "rg-${var.name}"
  location = var.location
  tags     = var.tags
}

resource "azurerm_service_plan" "service" {
  name                   = "asp-${var.name}"
  resource_group_name    = azurerm_resource_group.service.name
  location               = azurerm_resource_group.service.location
  os_type                = "Linux"
  sku_name               = var.sku_name
  worker_count           = var.capacity.default
  zone_balancing_enabled = var.zone_redundant
  tags                   = var.tags

  lifecycle {
    # Autoscale is the sole owner of the live worker count after creation.
    ignore_changes = [worker_count]

    precondition {
      condition     = !var.zone_redundant || var.capacity.minimum >= 2
      error_message = "Zone redundancy requires a minimum of two workers."
    }
  }
}

resource "azurerm_user_assigned_identity" "pull" {
  count               = local.acr ? 1 : 0
  name                = "id-${var.name}-pull"
  resource_group_name = azurerm_resource_group.service.name
  location            = azurerm_resource_group.service.location
  tags                = var.tags
}

resource "azurerm_role_assignment" "pull" {
  count                            = local.acr ? 1 : 0
  scope                            = var.acr_id
  role_definition_name             = "AcrPull"
  principal_id                     = azurerm_user_assigned_identity.pull[0].principal_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}

resource "azurerm_linux_web_app" "service" {
  name                                           = var.name
  location                                       = azurerm_resource_group.service.location
  resource_group_name                            = azurerm_resource_group.service.name
  service_plan_id                                = azurerm_service_plan.service.id
  https_only                                     = true
  public_network_access_enabled                  = true
  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = false
  app_settings                                   = local.app_settings["production"]
  tags                                           = var.tags

  identity {
    type         = local.acr ? "SystemAssigned, UserAssigned" : "SystemAssigned"
    identity_ids = azurerm_user_assigned_identity.pull[*].id
  }

  site_config {
    always_on                                     = true
    ftps_state                                    = "Disabled"
    http2_enabled                                 = true
    minimum_tls_version                           = "1.2"
    scm_minimum_tls_version                       = "1.2"
    scm_ip_restriction_default_action             = "Deny"
    health_check_path                             = var.health_check_path
    health_check_eviction_time_in_min             = 3
    container_registry_use_managed_identity       = local.acr
    container_registry_managed_identity_client_id = one(azurerm_user_assigned_identity.pull[*].client_id)

    application_stack {
      docker_image_name   = local.image_name
      docker_registry_url = var.image.registry_url
    }
  }

  sticky_settings {
    app_setting_names = concat(["APPLICATIONINSIGHTS_CONNECTION_STRING"], keys(var.environment_settings))
  }

  depends_on = [azurerm_role_assignment.pull]

  lifecycle {
    # Release automation owns image versions after bootstrap, including swaps.
    ignore_changes = [site_config[0].application_stack[0].docker_image_name]

    precondition {
      condition = length(setintersection(toset([
        for key in concat(keys(var.app_settings), keys(var.environment_settings)) : upper(key)
      ]), local.reserved_settings)) == 0
      error_message = "App settings cannot override module-managed container, health, warmup, swap, or telemetry settings."
    }

    precondition {
      condition     = var.enable_staging_slot || length(var.staging_allowed_cidrs) == 0
      error_message = "staging_allowed_cidrs requires the staging slot to be enabled."
    }
  }
}

resource "azurerm_linux_web_app_slot" "staging" {
  count                                          = var.enable_staging_slot ? 1 : 0
  name                                           = "staging"
  app_service_id                                 = azurerm_linux_web_app.service.id
  https_only                                     = true
  public_network_access_enabled                  = true
  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = false
  app_settings                                   = local.app_settings["staging"]
  tags                                           = var.tags

  identity {
    type         = local.acr ? "SystemAssigned, UserAssigned" : "SystemAssigned"
    identity_ids = azurerm_user_assigned_identity.pull[*].id
  }

  site_config {
    always_on                                     = true
    ftps_state                                    = "Disabled"
    http2_enabled                                 = true
    minimum_tls_version                           = "1.2"
    scm_minimum_tls_version                       = "1.2"
    health_check_path                             = var.health_check_path
    health_check_eviction_time_in_min             = 3
    container_registry_use_managed_identity       = local.acr
    container_registry_managed_identity_client_id = one(azurerm_user_assigned_identity.pull[*].client_id)
    ip_restriction_default_action                 = "Deny"
    scm_ip_restriction_default_action             = "Deny"

    application_stack {
      docker_image_name   = local.image_name
      docker_registry_url = var.image.registry_url
    }

    dynamic "ip_restriction" {
      for_each = sort(tolist(var.staging_allowed_cidrs))
      content {
        name       = "allow-${ip_restriction.key + 1}"
        priority   = 100 + ip_restriction.key
        action     = "Allow"
        ip_address = ip_restriction.value
      }
    }
  }

  lifecycle {
    ignore_changes = [site_config[0].application_stack[0].docker_image_name]
  }
}
