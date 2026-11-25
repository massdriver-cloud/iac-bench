locals {
  # Every resource is named <name>-<environment>-<purpose>.
  name_prefix = "${var.name}-${var.environment}"

  # Premium v3 is the only App Service family that delivers every guarantee this
  # module makes: Linux containers, zone redundancy, deployment slots, always-on
  # and autoscaling. SREs pick a size, the module picks the SKU.
  sku_by_size = {
    small  = "P1v3" # ~210 ACU, 3.5 GB RAM
    medium = "P2v3" # ~420 ACU, 7 GB RAM
    large  = "P3v3" # ~840 ACU, 14 GB RAM
  }

  common_tags = merge(var.tags, {
    application = var.name
    environment = var.environment
    managed_by  = "terraform"
    module      = "sre-app-service"
  })
}

locals {
  # Settings the module owns on behalf of every service it runs.
  managed_app_settings = {
    "APPLICATIONINSIGHTS_CONNECTION_STRING" = azurerm_application_insights.this.connection_string
    "WEBSITES_PORT"                         = tostring(var.container_port)
  }

  registry_app_settings = var.container_registry != null ? {
    "DOCKER_REGISTRY_SERVER_URL"      = "https://${var.container_registry.server}"
    "DOCKER_REGISTRY_SERVER_USERNAME" = var.container_registry.username
    "DOCKER_REGISTRY_SERVER_PASSWORD" = var.container_registry.password
  } : {}

  # SRE-supplied settings win over module-managed ones.
  app_settings = merge(local.managed_app_settings, local.registry_app_settings, var.app_settings)
}
