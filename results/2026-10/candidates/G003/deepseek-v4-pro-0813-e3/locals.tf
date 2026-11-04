locals {
  # Normalised resource naming: short, collision-resistant via a random suffix.
  suffix = random_id.suffix.hex

  name              = "${var.name}-${var.environment}"
  resource_group    = azurerm_resource_group.this.name
  app_service_plan  = azurerm_service_plan.this.name
  app_insights_name = "${local.name}-insights"

  # Zone redundancy requires a Premium v3 (or v2) SKU.
  zone_capable = can(regex("^PremiumV[23]$", var.sku.tier)) || can(regex("^P[0-9]v[23]$", var.sku.size))

  # Opinionated defaults chosen per environment so SREs don't tune internals.
  env = {
    dev = {
      ftps_state      = "AllAllowed"
      min_tls_version = "1.2"
      http2           = true
    }
    stg = {
      ftps_state      = "FtpsOnly"
      min_tls_version = "1.2"
      http2           = true
    }
    prd = {
      ftps_state      = "Disabled"
      min_tls_version = "1.2"
      http2           = true
    }
  }[var.environment]

  effective_zone_redundant = local.zone_capable ? var.zone_redundant : false

  docker_username = var.registry.use_managed_identity ? "__token__" : coalesce(var.registry.username, "")

  # Container registry config varies by authn mechanism.
  container_app_settings = var.registry.use_managed_identity ? {
    DOCKER_REGISTRY_SERVER_URL      = "https://${var.registry.server_url}"
    DOCKER_REGISTRY_SERVER_USERNAME = local.docker_username
    DOCKER_ENABLE_CI                = "true"
    } : {
    DOCKER_REGISTRY_SERVER_URL      = var.registry.server_url
    DOCKER_REGISTRY_SERVER_USERNAME = var.registry.username
    DOCKER_ENABLE_CI                = "true"
    DOCKER_REGISTRY_SERVER_PASSWORD = var.registry.password
  }

  health_check_settings = var.health_check_path == "" ? {} : {
    WEBSITE_HEALTHCHECK_MAXPINGFAILURES           = "10"
    WEBSITE_HEALTHCHECK_MAXUNHEALTHYWORKERPERCENT = "100"
  }

  app_insights_setting = var.app_insights_enabled ? {
    APPLICATIONINSIGHTS_CONNECTION_STRING      = azurerm_application_insights.this[0].connection_string
    ApplicationInsightsAgent_EXTENSION_VERSION = "~3"
  } : {}

  standard_settings = merge(
    {
      WEBSITES_ENABLE_APP_SERVICE_STORAGE = "false"
      WEBSITES_PORT                       = tostring(var.port)
      DOCKER_ENABLE_CI                    = "true"
      WEBSITE_HTTPLOGGING_RETENTION_DAYS  = "7"
    },
    local.container_app_settings,
    local.health_check_settings,
    local.app_insights_setting
  )

  # Merge standard settings with SRE-provided extras (extras win).
  app_settings_computed = merge(local.standard_settings, var.app_settings, var.app_settings_sensitive)

  # Full set of requested ip restrictions with defaults filled.
  ip_restrictions = [
    for r in var.ip_restrictions : {
      name                      = r.name
      priority                  = r.priority
      ip_address                = r.ip
      action                    = r.action
      service_tag               = null
      virtual_network_subnet_id = null
    }
  ]
}

resource "random_id" "suffix" {
  byte_length = 4
}