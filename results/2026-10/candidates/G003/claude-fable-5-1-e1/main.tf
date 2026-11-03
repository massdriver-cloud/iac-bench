locals {
  rg_name = coalesce(var.resource_group_name, "${var.name}-rg")

  sku_tier_letter = substr(var.sku_name, 0, 1)
  # Basic tier supports manual scale only: no autoscale, no slots, no zones.
  is_basic   = local.sku_tier_letter == "B"
  is_premium = local.sku_tier_letter == "P"

  autoscale_supported = !local.is_basic
  autoscale_dynamic   = local.autoscale_supported && var.capacity.max > var.capacity.min

  use_acr_identity = var.acr_id != null

  # Baseline container settings; user-supplied settings override these.
  base_app_settings = {
    WEBSITES_PORT                         = tostring(var.container_port)
    WEBSITES_ENABLE_APP_SERVICE_STORAGE   = "false"
    WEBSITES_CONTAINER_START_TIME_LIMIT   = tostring(var.container_start_time_limit_seconds)
    DOCKER_ENABLE_CI                      = "false"
    APPLICATIONINSIGHTS_CONNECTION_STRING = azurerm_application_insights.this.connection_string
  }

  app_settings = merge(local.base_app_settings, var.app_settings, var.sensitive_app_settings)

  sticky_app_setting_names = distinct(concat(["APPLICATIONINSIGHTS_CONNECTION_STRING"], var.sticky_app_setting_names))

  ip_restrictions = [
    for idx, cidr in var.allowed_ip_ranges : {
      name       = "allow-${idx}"
      ip_address = cidr
      priority   = 100 + idx
    }
  ]

  restrict_inbound = length(local.ip_restrictions) > 0

  tags = merge(var.tags, { "managed-by" = "opentofu", "service" = var.name })
}

############################################
# Guard rails that need cross-variable context
############################################

resource "terraform_data" "sku_guard" {
  lifecycle {
    precondition {
      condition     = !(local.is_basic && var.capacity.max != var.capacity.min)
      error_message = "Basic SKUs (B1-B3) do not support autoscale: set capacity.min == capacity.max or move to Standard/Premium."
    }
    precondition {
      condition     = !(local.is_basic && var.enable_staging_slot)
      error_message = "Deployment slots require a Standard or Premium SKU."
    }
    precondition {
      condition     = !var.zone_redundant || (local.is_premium && var.capacity.min >= 3)
      error_message = "zone_redundant requires a Premium v2/v3 SKU and capacity.min >= 3."
    }
    precondition {
      condition     = !(var.acr_id != null && (var.container_registry_username != null || var.container_registry_password != null))
      error_message = "Use either acr_id (managed identity pull) or container_registry_username/password, not both."
    }
    precondition {
      condition     = (var.container_registry_username == null) == (var.container_registry_password == null)
      error_message = "container_registry_username and container_registry_password must be set together."
    }
  }
}

############################################
# Resource group
############################################

resource "azurerm_resource_group" "this" {
  count = var.create_resource_group ? 1 : 0

  name     = local.rg_name
  location = var.location
  tags     = local.tags
}

data "azurerm_resource_group" "existing" {
  count = var.create_resource_group ? 0 : 1

  name = local.rg_name
}

locals {
  resource_group_name = var.create_resource_group ? azurerm_resource_group.this[0].name : data.azurerm_resource_group.existing[0].name
}

############################################
# App Service Plan
############################################

resource "azurerm_service_plan" "this" {
  name                = "${var.name}-plan"
  resource_group_name = local.resource_group_name
  location            = var.location
  os_type             = "Linux"
  sku_name            = var.sku_name

  worker_count           = var.capacity.min
  zone_balancing_enabled = var.zone_redundant

  tags = local.tags

  lifecycle {
    # Instance count is owned by the autoscale setting after creation so that
    # scale events never show up as drift and tofu never fights autoscale.
    ignore_changes = [worker_count]
  }
}

############################################
# Web App
############################################

resource "azurerm_linux_web_app" "this" {
  name                = var.name
  resource_group_name = local.resource_group_name
  location            = var.location
  service_plan_id     = azurerm_service_plan.this.id

  https_only                    = true
  client_affinity_enabled       = false # stateless HTTP APIs: no session pinning
  public_network_access_enabled = var.public_network_access_enabled
  virtual_network_subnet_id     = var.vnet_integration_subnet_id

  # Containers are pulled from a registry; no code publishing channels needed.
  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = false

  identity {
    type = "SystemAssigned"
  }

  site_config {
    always_on                               = true
    ftps_state                              = "Disabled"
    minimum_tls_version                     = "1.2"
    http2_enabled                           = true
    health_check_path                       = var.health_check_path
    health_check_eviction_time_in_min       = var.health_check_eviction_minutes
    container_registry_use_managed_identity = local.use_acr_identity
    vnet_route_all_enabled                  = var.vnet_integration_subnet_id != null
    ip_restriction_default_action           = local.restrict_inbound ? "Deny" : "Allow"
    scm_ip_restriction_default_action       = local.restrict_inbound ? "Deny" : "Allow"
    load_balancing_mode                     = "LeastRequests"

    application_stack {
      docker_image_name        = var.container_image
      docker_registry_url      = var.container_registry_url
      docker_registry_username = var.container_registry_username
      docker_registry_password = var.container_registry_password
    }

    dynamic "ip_restriction" {
      for_each = local.ip_restrictions
      content {
        name       = ip_restriction.value.name
        ip_address = ip_restriction.value.ip_address
        action     = "Allow"
        priority   = ip_restriction.value.priority
      }
    }

    dynamic "scm_ip_restriction" {
      for_each = local.ip_restrictions
      content {
        name       = scm_ip_restriction.value.name
        ip_address = scm_ip_restriction.value.ip_address
        action     = "Allow"
        priority   = scm_ip_restriction.value.priority
      }
    }
  }

  app_settings = local.app_settings

  sticky_settings {
    app_setting_names = local.sticky_app_setting_names
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

  tags = local.tags

  depends_on = [terraform_data.sku_guard]
}

############################################
# ACR pull via managed identity
############################################

resource "azurerm_role_assignment" "acr_pull" {
  count = local.use_acr_identity ? 1 : 0

  scope                = var.acr_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_linux_web_app.this.identity[0].principal_id
}
