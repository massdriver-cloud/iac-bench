# ---------------------------------------------------------------------------
# The app (Linux container)
# ---------------------------------------------------------------------------

locals {
  image_tag = (
    can(regex(":", var.docker_image))
    ? element(split(":", var.docker_image), length(split(":", var.docker_image)) - 1)
    : "latest"
  )

  # The image name for the Docker app stack. Tag may already be embedded in
  # the image string; if so we pass it through unchanged, otherwise append.
  docker_image_name = (
    can(regex(":", var.docker_image))
    ? var.docker_image
    : "${var.docker_image}:${local.image_tag}"
  )

  use_managed_identity_for_registry = can(regex("azurecr\\.io", var.docker_registry_url))

  # A private registry that isn't ACR needs explicit credentials in settings.
  needs_registry_credentials = !local.use_managed_identity_for_registry && var.docker_registry_username != null

  registry_app_settings = local.needs_registry_credentials ? {
    DOCKER_REGISTRY_SERVER_USERNAME = var.docker_registry_username
    DOCKER_REGISTRY_SERVER_PASSWORD = var.docker_registry_password
  } : {}
}

resource "azurerm_linux_web_app" "this" {
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name
  service_plan_id     = local.plan_id

  https_only = true

  # Harden publishing by disabling basic-auth FTP and Web Deploy.
  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = false

  identity {
    type = var.system_identity_enabled ? "SystemAssigned" : "None"
  }

  site_config {
    always_on                         = var.always_on
    http2_enabled                     = true
    websockets_enabled                = true
    health_check_path                 = var.health_check_path
    health_check_eviction_time_in_min = var.health_check_eviction_time_in_min
    app_command_line                  = var.startup_command
    ftps_state                        = "Disabled"

    application_stack {
      docker_image_name        = local.docker_image_name
      docker_registry_url      = var.docker_registry_url
      docker_registry_username = var.docker_registry_username
      docker_registry_password = var.docker_registry_password
    }
  }

  app_settings = merge(
    local.base_app_settings,
    local.registry_app_settings,
    {
      WEBSITES_PORT = tostring(var.port)
    }
  )

  lifecycle {
    ignore_changes = [
      # The platform rewrites these keys after the container is deployed.
      app_settings["DOCKER_CUSTOM_IMAGE_NAME"],
    ]
  }

  tags = local.common_tags
}

# ---------------------------------------------------------------------------
# Staging deployment slot (canary/rollout)
# ---------------------------------------------------------------------------

resource "azurerm_linux_web_app_slot" "staging" {
  count          = var.slot_enabled ? 1 : 0
  name           = "staging"
  app_service_id = azurerm_linux_web_app.this.id

  https_only = true

  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = false

  identity {
    type = var.system_identity_enabled ? "SystemAssigned" : "None"
  }

  site_config {
    always_on                         = var.always_on
    http2_enabled                     = true
    websockets_enabled                = true
    health_check_path                 = var.health_check_path
    health_check_eviction_time_in_min = var.health_check_eviction_time_in_min
    app_command_line                  = var.startup_command
    ftps_state                        = "Disabled"

    application_stack {
      docker_image_name        = local.docker_image_name
      docker_registry_url      = var.docker_registry_url
      docker_registry_username = var.docker_registry_username
      docker_registry_password = var.docker_registry_password
    }
  }

  app_settings = merge(
    local.base_app_settings,
    local.registry_app_settings,
    {
      WEBSITES_PORT = tostring(var.port)
    }
  )

  tags = local.common_tags
}

# ---------------------------------------------------------------------------
# Traffic routing (percentage-based rollout)
#
# Percentage-based routing (e.g. staging_traffic = 20) is applied by pointing
# the "active" production routing at the staging slot. SRE rollout tooling
# adjusts the percentage via `az webapp traffic-routing set` during a release;
# this resource establishes the slot so routing can be enabled at any time.
# ---------------------------------------------------------------------------

resource "azurerm_web_app_active_slot" "traffic" {
  count   = var.slot_enabled ? 1 : 0
  slot_id = azurerm_linux_web_app_slot.staging[0].id
}