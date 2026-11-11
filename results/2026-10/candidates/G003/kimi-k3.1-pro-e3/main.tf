locals {
  resource_group_name = coalesce(var.resource_group_name, "${var.name}-rg")

  default_tags = {
    "managed-by" = "opentofu"
    "module"     = "sre-app-service"
    "service"    = var.name
  }
  tags = merge(local.default_tags, var.tags)

  use_registry_managed_identity = var.container_registry_use_managed_identity && var.container_registry_username == null

  managed_app_settings = {
    "APPLICATIONINSIGHTS_CONNECTION_STRING"      = azurerm_application_insights.this.connection_string
    "APPINSIGHTS_INSTRUMENTATIONKEY"             = azurerm_application_insights.this.instrumentation_key
    "ApplicationInsightsAgent_EXTENSION_VERSION" = "~3"
    "DOCKER_ENABLE_CI"                           = "false"
    "WEBSITES_CONTAINER_START_TIME_LIMIT"        = tostring(var.container_start_time_limit_seconds)
    "WEBSITES_ENABLE_APP_SERVICE_STORAGE"        = "false"
    "WEBSITES_PORT"                              = tostring(var.container_port)
  }

  production_app_settings = merge(var.app_settings, local.managed_app_settings)
  staging_app_settings    = merge(local.production_app_settings, var.staging_app_settings)

  service_plan_id = one(concat(
    azurerm_service_plan.autoscaled[*].id,
    azurerm_service_plan.fixed[*].id,
  ))
  service_plan_name = one(concat(
    azurerm_service_plan.autoscaled[*].name,
    azurerm_service_plan.fixed[*].name,
  ))
}

resource "azurerm_resource_group" "this" {
  count = var.create_resource_group ? 1 : 0

  name     = local.resource_group_name
  location = var.location
  tags     = local.tags
}

data "azurerm_resource_group" "this" {
  count = var.create_resource_group ? 0 : 1

  name = local.resource_group_name
}

locals {
  resource_group_location = var.create_resource_group ? azurerm_resource_group.this[0].location : data.azurerm_resource_group.this[0].location
  resource_group_id       = var.create_resource_group ? azurerm_resource_group.this[0].id : data.azurerm_resource_group.this[0].id
}

resource "azurerm_user_assigned_identity" "this" {
  name                = "${var.name}-id"
  resource_group_name = local.resource_group_name
  location            = local.resource_group_location
  tags                = local.tags
}

resource "azurerm_role_assignment" "acr_pull" {
  count = local.use_registry_managed_identity && var.container_registry_id != null ? 1 : 0

  scope                = var.container_registry_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.this.principal_id
  principal_type       = "ServicePrincipal"
}

# Two resource instances let Terraform ignore autoscale-owned instance-count drift
# without also ignoring deliberate capacity changes on a fixed-size plan.
resource "azurerm_service_plan" "autoscaled" {
  count = var.autoscale_enabled ? 1 : 0

  name                     = "${var.name}-asp"
  resource_group_name      = local.resource_group_name
  location                 = local.resource_group_location
  os_type                  = "Linux"
  sku_name                 = var.plan_sku_name
  worker_count             = var.autoscale_default_capacity
  zone_balancing_enabled   = var.zone_balancing_enabled
  per_site_scaling_enabled = false
  tags                     = local.tags

  lifecycle {
    ignore_changes = [worker_count]

    precondition {
      condition = (
        var.autoscale_minimum_capacity <= var.autoscale_default_capacity &&
        var.autoscale_default_capacity <= var.autoscale_maximum_capacity
      )
      error_message = "autoscale_default_capacity must be between autoscale_minimum_capacity and autoscale_maximum_capacity."
    }

    precondition {
      condition     = !var.zone_balancing_enabled || (var.autoscale_minimum_capacity >= 3 && var.autoscale_default_capacity >= 3)
      error_message = "Zone balancing requires autoscale_minimum_capacity and autoscale_default_capacity of at least 3."
    }
  }
}

resource "azurerm_service_plan" "fixed" {
  count = var.autoscale_enabled ? 0 : 1

  name                     = "${var.name}-asp"
  resource_group_name      = local.resource_group_name
  location                 = local.resource_group_location
  os_type                  = "Linux"
  sku_name                 = var.plan_sku_name
  worker_count             = var.plan_worker_count
  zone_balancing_enabled   = var.zone_balancing_enabled
  per_site_scaling_enabled = false
  tags                     = local.tags

  lifecycle {
    precondition {
      condition     = !var.zone_balancing_enabled || var.plan_worker_count >= 3
      error_message = "Zone balancing requires plan_worker_count of at least 3."
    }
  }
}
