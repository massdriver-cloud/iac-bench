locals {
  environments = var.enable_staging_slot ? toset(["production", "staging"]) : toset(["production"])
  tags         = merge(var.tags, { managed-by = "opentofu", service = var.name })
  ingress_rules = {
    for index, cidr in sort(tolist(var.ingress_cidrs)) : "client-${index}" => { cidr = cidr, priority = 100 + index }
  }
  management_rules = {
    for index, cidr in sort(tolist(var.management_cidrs)) : "operator-${index}" => { cidr = cidr, priority = 100 + index }
  }
  platform_settings = {
    WEBSITES_PORT                                 = tostring(var.container_port)
    WEBSITES_ENABLE_APP_SERVICE_STORAGE           = "false"
    WEBSITES_CONTAINER_START_TIME_LIMIT           = "300"
    WEBSITE_HEALTHCHECK_MAXPINGFAILURES           = "3"
    WEBSITE_HEALTHCHECK_MAXUNHEALTHYWORKERPERCENT = "50"
    WEBSITE_WARMUP_PATH                           = var.health_check_path
    WEBSITE_WARMUP_STATUSES                       = "200"
    WEBSITE_SWAP_WARMUP_PING_PATH                 = var.health_check_path
    WEBSITE_SWAP_WARMUP_PING_STATUSES             = "200"
  }
  # Only setting names are declassified; setting values remain sensitive.
  sticky_settings = sort(tolist(setunion(
    var.sticky_app_setting_names,
    toset(nonsensitive(keys(var.staging_app_settings))),
    toset(["APP_ENVIRONMENT", "APPLICATIONINSIGHTS_CONNECTION_STRING", "APPINSIGHTS_INSTRUMENTATIONKEY"])
  )))
}

resource "azurerm_resource_group" "this" {
  name     = "${var.name}-rg"
  location = var.location
  tags     = local.tags
}

resource "azurerm_service_plan" "this" {
  name                   = "${var.name}-plan"
  resource_group_name    = azurerm_resource_group.this.name
  location               = azurerm_resource_group.this.location
  os_type                = "Linux"
  sku_name               = var.sku_name
  worker_count           = var.capacity.minimum
  zone_balancing_enabled = var.capacity.zone_redundant
  tags                   = local.tags

  # Azure Monitor owns the live worker count. The autoscale profile owns the floor.
  lifecycle {
    ignore_changes = [worker_count]
  }
}

# Pre-created identities allow image-pull grants before creating the app.
# Runtime SDKs use each slot's separate system-assigned identity by default.
resource "azurerm_user_assigned_identity" "app" {
  for_each            = local.environments
  name                = "${var.name}-${each.key}"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  tags                = local.tags
}

resource "azurerm_role_assignment" "acr_pull" {
  for_each                         = var.registry.acr_resource_id == null ? toset([]) : local.environments
  scope                            = var.registry.acr_resource_id
  role_definition_name             = "AcrPull"
  principal_id                     = azurerm_user_assigned_identity.app[each.key].principal_id
  skip_service_principal_aad_check = true
}

resource "azurerm_linux_web_app" "production" {
  name                                           = var.name
  resource_group_name                            = azurerm_resource_group.this.name
  location                                       = azurerm_resource_group.this.location
  service_plan_id                                = azurerm_service_plan.this.id
  https_only                                     = true
  public_network_access_enabled                  = true
  client_affinity_enabled                        = false
  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = false
  virtual_network_subnet_id                      = var.integration_subnet_id
  vnet_image_pull_enabled                        = var.integration_subnet_id != null
  key_vault_reference_identity_id                = azurerm_user_assigned_identity.app["production"].id
  tags                                           = local.tags

  identity {
    type         = "SystemAssigned, UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.app["production"].id]
  }

  site_config {
    always_on                                     = true
    http2_enabled                                 = true
    minimum_tls_version                           = "1.2"
    scm_minimum_tls_version                       = "1.2"
    ftps_state                                    = "Disabled"
    remote_debugging_enabled                      = false
    health_check_path                             = var.health_check_path
    health_check_eviction_time_in_min             = 5
    vnet_route_all_enabled                        = var.integration_subnet_id != null
    container_registry_use_managed_identity       = var.registry.acr_resource_id != null
    container_registry_managed_identity_client_id = var.registry.acr_resource_id == null ? null : azurerm_user_assigned_identity.app["production"].client_id
    ip_restriction_default_action                 = length(var.ingress_cidrs) == 0 ? "Allow" : "Deny"
    scm_use_main_ip_restriction                   = false
    scm_ip_restriction_default_action             = "Deny"

    application_stack {
      docker_image_name   = var.container_image
      docker_registry_url = var.registry.url
    }
    dynamic "ip_restriction" {
      for_each = local.ingress_rules
      content {
        name       = ip_restriction.key
        ip_address = ip_restriction.value.cidr
        priority   = ip_restriction.value.priority
        action     = "Allow"
      }
    }
    dynamic "scm_ip_restriction" {
      for_each = local.management_rules
      content {
        name       = scm_ip_restriction.key
        ip_address = scm_ip_restriction.value.cidr
        priority   = scm_ip_restriction.value.priority
        action     = "Allow"
      }
    }
  }

  app_settings = merge(var.app_settings, local.platform_settings, {
    APP_ENVIRONMENT                       = "production"
    APPLICATIONINSIGHTS_CONNECTION_STRING = azurerm_application_insights.app["production"].connection_string
    APPINSIGHTS_INSTRUMENTATIONKEY        = azurerm_application_insights.app["production"].instrumentation_key
  })

  sticky_settings {
    app_setting_names = local.sticky_settings
  }

  logs {
    detailed_error_messages = false
    failed_request_tracing  = false
    http_logs {
      file_system {
        retention_in_days = 7
        retention_in_mb   = 35
      }
    }
    application_logs {
      file_system_level = "Information"
    }
  }

  depends_on = [azurerm_role_assignment.acr_pull]
}

resource "azurerm_linux_web_app_slot" "staging" {
  count                                          = var.enable_staging_slot ? 1 : 0
  name                                           = "staging"
  app_service_id                                 = azurerm_linux_web_app.production.id
  https_only                                     = true
  public_network_access_enabled                  = true
  client_affinity_enabled                        = false
  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = false
  virtual_network_subnet_id                      = var.integration_subnet_id
  vnet_image_pull_enabled                        = var.integration_subnet_id != null
  key_vault_reference_identity_id                = azurerm_user_assigned_identity.app["staging"].id
  tags                                           = local.tags

  identity {
    type         = "SystemAssigned, UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.app["staging"].id]
  }

  site_config {
    always_on                                     = true
    http2_enabled                                 = true
    minimum_tls_version                           = "1.2"
    scm_minimum_tls_version                       = "1.2"
    ftps_state                                    = "Disabled"
    remote_debugging_enabled                      = false
    health_check_path                             = var.health_check_path
    health_check_eviction_time_in_min             = 5
    vnet_route_all_enabled                        = var.integration_subnet_id != null
    container_registry_use_managed_identity       = var.registry.acr_resource_id != null
    container_registry_managed_identity_client_id = var.registry.acr_resource_id == null ? null : azurerm_user_assigned_identity.app["staging"].client_id
    ip_restriction_default_action                 = "Deny"
    scm_use_main_ip_restriction                   = false
    scm_ip_restriction_default_action             = "Deny"

    application_stack {
      docker_image_name   = coalesce(var.staging_container_image, var.container_image)
      docker_registry_url = var.registry.url
    }
    dynamic "ip_restriction" {
      for_each = local.management_rules
      content {
        name       = ip_restriction.key
        ip_address = ip_restriction.value.cidr
        priority   = ip_restriction.value.priority
        action     = "Allow"
      }
    }
    dynamic "scm_ip_restriction" {
      for_each = local.management_rules
      content {
        name       = scm_ip_restriction.key
        ip_address = scm_ip_restriction.value.cidr
        priority   = scm_ip_restriction.value.priority
        action     = "Allow"
      }
    }
  }

  app_settings = merge(var.app_settings, var.staging_app_settings, local.platform_settings, {
    APP_ENVIRONMENT                       = "staging"
    APPLICATIONINSIGHTS_CONNECTION_STRING = azurerm_application_insights.app["staging"].connection_string
    APPINSIGHTS_INSTRUMENTATIONKEY        = azurerm_application_insights.app["staging"].instrumentation_key
  })

  logs {
    detailed_error_messages = false
    failed_request_tracing  = false
    http_logs {
      file_system {
        retention_in_days = 7
        retention_in_mb   = 35
      }
    }
    application_logs {
      file_system_level = "Information"
    }
  }

  depends_on = [azurerm_role_assignment.acr_pull]
}
