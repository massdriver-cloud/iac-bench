# ------------------------------------------------------------------------------
# App Service (the HTTP API) + deployment slot
# ------------------------------------------------------------------------------

resource "azurerm_linux_web_app" "this" {
  name                = "app-${local.app_name}"
  resource_group_name = var.resource_group_name
  location            = var.location
  service_plan_id     = azurerm_service_plan.this.id

  https_only                = var.https_only
  client_affinity_enabled   = false
  virtual_network_subnet_id = var.virtual_network_subnet_id

  identity {
    type = "SystemAssigned"
  }

  site_config {
    always_on                         = var.always_on
    health_check_path                 = var.health_check_path
    health_check_eviction_time_in_min = 10
    vnet_route_all_enabled            = var.virtual_network_subnet_id != null
    http2_enabled                     = true
    minimum_tls_version               = "1.2"
    worker_count                      = var.worker_count

    application_stack {
      docker_image     = local.docker_image_name
      docker_image_tag = local.docker_image_tag
    }

    dynamic "ip_restriction" {
      for_each = var.allowed_ip_ranges
      content {
        name       = "allowlisted-${ip_restriction.key}"
        ip_address = ip_restriction.value
        priority   = 100 + ip_restriction.key
        action     = "Allow"
      }
    }
  }

  app_settings = merge(
    {
      WEBSITES_PORT                       = tostring(var.container_port)
      WEBSITES_ENABLE_APP_SERVICE_STORAGE = "false"
      DOCKER_REGISTRY_SERVER_URL          = var.docker_registry_url
    },
    var.docker_registry_username != null ? {
      DOCKER_REGISTRY_SERVER_USERNAME = var.docker_registry_username
      DOCKER_REGISTRY_SERVER_PASSWORD = var.docker_registry_password
    } : {},
    var.application_insights_connection_string != null ? {
      APPLICATIONINSIGHTS_CONNECTION_STRING = var.application_insights_connection_string
    } : {},
  )

  lifecycle {
    # The container image tag is rolled by CI/CD (e.g. flux/argo or a deploy
    # pipeline) outside of Terraform, so drift on the tag is expected and
    # should not force a plan diff. The image name/repo stays managed here.
    ignore_changes = [
      site_config[0].application_stack[0].docker_image_tag,
    ]
  }

  tags = local.common_tags
}

resource "azurerm_app_service_virtual_network_swift_connection" "this" {
  count = var.virtual_network_subnet_id != null ? 1 : 0

  app_service_id = azurerm_linux_web_app.this.id
  subnet_id      = var.virtual_network_subnet_id
}

resource "azurerm_linux_web_app_slot" "staging" {
  count = var.deployment_slot ? 1 : 0

  name                      = "staging"
  app_service_id            = azurerm_linux_web_app.this.id
  https_only                = var.https_only
  virtual_network_subnet_id = var.virtual_network_subnet_id

  identity {
    type = "SystemAssigned"
  }

  site_config {
    always_on           = var.always_on
    health_check_path   = var.health_check_path
    http2_enabled       = true
    minimum_tls_version = "1.2"
    worker_count        = var.worker_count

    application_stack {
      docker_image     = local.docker_image_name
      docker_image_tag = local.docker_image_tag
    }
  }

  app_settings = merge(
    {
      WEBSITES_PORT                       = tostring(var.container_port)
      WEBSITES_ENABLE_APP_SERVICE_STORAGE = "false"
      DOCKER_REGISTRY_SERVER_URL          = var.docker_registry_url
    },
    var.docker_registry_username != null ? {
      DOCKER_REGISTRY_SERVER_USERNAME = var.docker_registry_username
      DOCKER_REGISTRY_SERVER_PASSWORD = var.docker_registry_password
    } : {},
    var.application_insights_connection_string != null ? {
      APPLICATIONINSIGHTS_CONNECTION_STRING = var.application_insights_connection_string
    } : {},
  )

  lifecycle {
    ignore_changes = [
      site_config[0].application_stack[0].docker_image_tag,
    ]
  }

  tags = local.common_tags
}

resource "azurerm_app_service_slot_virtual_network_swift_connection" "staging" {
  count = (var.deployment_slot && var.virtual_network_subnet_id != null) ? 1 : 0

  slot_name      = azurerm_linux_web_app_slot.staging[0].name
  app_service_id = azurerm_linux_web_app.this.id
  subnet_id      = var.virtual_network_subnet_id
}