locals {
  resource_group_name = coalesce(var.resource_group_name, "${var.name}-rg")

  tags = merge(var.tags, {
    service   = var.name
    managedBy = "opentofu"
  })

  # Settings the module owns. User-supplied app_settings are merged underneath
  # these so a service team cannot accidentally break platform wiring.
  platform_app_settings = {
    WEBSITES_PORT                         = tostring(var.container_port)
    WEBSITES_ENABLE_APP_SERVICE_STORAGE   = "false"
    APPLICATIONINSIGHTS_CONNECTION_STRING = azurerm_application_insights.this.connection_string
    DOCKER_ENABLE_CI                      = "false"
  }

  production_app_settings = merge(var.app_settings, local.platform_app_settings, {
    ENVIRONMENT = "production"
  })

  staging_app_settings = merge(var.app_settings, local.platform_app_settings, {
    ENVIRONMENT = "staging"
  })

  # ENVIRONMENT is slot-sticky so a swap never carries the staging marker into
  # production (or vice versa). Everything else swaps with the code.
  sticky_app_setting_names = ["ENVIRONMENT"]

  effective_min_instances = var.autoscale_enabled ? var.autoscale_min_instances : var.instance_count
}

resource "azurerm_resource_group" "this" {
  name     = local.resource_group_name
  location = var.location
  tags     = local.tags
}

###############################################################################
# Capacity: the App Service plan
###############################################################################

resource "azurerm_service_plan" "this" {
  name                = "${var.name}-plan"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  os_type             = "Linux"
  sku_name            = var.sku_name

  # When autoscale owns the instance count we must not also pin worker_count,
  # otherwise every apply would fight the autoscaler.
  worker_count           = var.autoscale_enabled ? null : var.instance_count
  zone_balancing_enabled = var.zone_balancing_enabled
  tags                   = local.tags

  lifecycle {
    precondition {
      condition     = !var.autoscale_enabled || can(regex("^(S|P|I|WS)", var.sku_name))
      error_message = "autoscale_enabled requires a Standard (S*), Premium (P*/I*), or Workflow Standard (WS*) SKU; Basic SKUs cannot autoscale."
    }
    precondition {
      condition     = !var.zone_balancing_enabled || can(regex("^P[0-9]+v[23]$", var.sku_name))
      error_message = "zone_balancing_enabled requires a Premium v2/v3 SKU (e.g. P1v3)."
    }
    precondition {
      condition     = !var.zone_balancing_enabled || local.effective_min_instances >= 3
      error_message = "zone_balancing_enabled requires at least 3 instances (set autoscale_min_instances or instance_count >= 3)."
    }
    precondition {
      condition     = !var.autoscale_enabled || (var.autoscale_min_instances <= var.instance_count && var.instance_count <= var.autoscale_max_instances)
      error_message = "autoscale bounds must satisfy: autoscale_min_instances <= instance_count <= autoscale_max_instances."
    }
  }
}

###############################################################################
# The service: production web app
###############################################################################

resource "azurerm_linux_web_app" "this" {
  name                = var.name
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  service_plan_id     = azurerm_service_plan.this.id

  https_only                    = true
  public_network_access_enabled = true
  client_affinity_enabled       = false # stateless HTTP APIs; no ARR affinity cookie
  virtual_network_subnet_id     = var.vnet_integration_subnet_id

  # No shared-secret publishing endpoints; deployments go through slots and
  # Entra ID-authenticated tooling.
  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = false

  app_settings = local.production_app_settings

  identity {
    type = "SystemAssigned"
  }

  site_config {
    always_on                               = true
    app_command_line                        = var.startup_command
    http2_enabled                           = true
    minimum_tls_version                     = "1.2"
    ftps_state                              = "Disabled"
    scm_minimum_tls_version                 = "1.2"
    use_32_bit_worker                       = false
    health_check_path                       = var.health_check_path
    health_check_eviction_time_in_min       = var.health_check_eviction_time_in_min
    vnet_route_all_enabled                  = var.vnet_integration_subnet_id != null
    container_registry_use_managed_identity = var.container_registry_use_managed_identity

    application_stack {
      docker_image_name        = var.container_image
      docker_registry_url      = var.container_registry_url
      docker_registry_username = var.container_registry_username
      docker_registry_password = var.container_registry_password
    }
  }

  sticky_settings {
    app_setting_names = local.sticky_app_setting_names
  }

  tags = local.tags

  lifecycle {
    precondition {
      condition     = !var.container_registry_use_managed_identity || var.container_registry_username == null
      error_message = "Use either container_registry_use_managed_identity or registry username/password, not both."
    }
  }
}

###############################################################################
# Rollouts: staging slot (deploy -> warm up -> swap, driven by the pipeline)
###############################################################################

resource "azurerm_linux_web_app_slot" "staging" {
  count = var.staging_slot_enabled ? 1 : 0

  name           = "staging"
  app_service_id = azurerm_linux_web_app.this.id

  https_only                    = true
  public_network_access_enabled = true
  client_affinity_enabled       = false
  virtual_network_subnet_id     = var.vnet_integration_subnet_id

  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = false

  app_settings = local.staging_app_settings

  identity {
    type = "SystemAssigned"
  }

  site_config {
    always_on                               = true
    app_command_line                        = var.startup_command
    http2_enabled                           = true
    minimum_tls_version                     = "1.2"
    ftps_state                              = "Disabled"
    scm_minimum_tls_version                 = "1.2"
    use_32_bit_worker                       = false
    health_check_path                       = var.health_check_path
    health_check_eviction_time_in_min       = var.health_check_eviction_time_in_min
    vnet_route_all_enabled                  = var.vnet_integration_subnet_id != null
    container_registry_use_managed_identity = var.container_registry_use_managed_identity

    application_stack {
      docker_image_name        = var.container_image
      docker_registry_url      = var.container_registry_url
      docker_registry_username = var.container_registry_username
      docker_registry_password = var.container_registry_password
    }
  }

  tags = local.tags
}
