# ---------------------------------------------------------------------------
# Base: resource group + App Service Plan
# ---------------------------------------------------------------------------

resource "azurerm_resource_group" "this" {
  name     = local.resource_group_name
  location = var.location
  tags     = local.common_tags
}

resource "azurerm_service_plan" "this" {
  name                = "${var.service_name}-plan"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location

  os_type  = "Linux"
  sku_name = var.sku_name

  # Baseline instance count. With autoscale enabled the autoscale profile
  # takes over day-to-day capacity between min and max.
  worker_count           = var.worker_count
  zone_balancing_enabled = var.zone_balancing_enabled

  tags = local.common_tags
}

# ---------------------------------------------------------------------------
# The service itself: Linux Web App running the team's container
# ---------------------------------------------------------------------------

resource "azurerm_linux_web_app" "this" {
  name                = var.service_name
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  service_plan_id     = azurerm_service_plan.this.id

  # Availability / hardening defaults.
  https_only                    = true
  client_affinity_enabled       = false # stateless HTTP APIs get no session affinity cookie
  public_network_access_enabled = var.public_network_access_enabled

  # Egress integration, if the service talks to private backends.
  virtual_network_subnet_id = var.vnet_integration_subnet_id

  tags = local.common_tags

  # System-assigned identity: lets the service authenticate to Azure services
  # (Key Vault, ACR, ...) without shipped secrets.
  identity {
    type = "SystemAssigned"
  }

  site_config {
    # Availability: no cold starts from idle-unloading.
    always_on = var.always_on

    # Health: the platform pings this path on every instance; instances that
    # stay unhealthy past the eviction window are replaced, and failed pings
    # drain them from rotation before users notice.
    health_check_path                 = var.health_check_path
    health_check_eviction_time_in_min = var.health_check_eviction_time_in_min

    http2_enabled       = var.http2_enabled
    minimum_tls_version = var.minimum_tls_version
    ftps_state          = var.ftps_state

    app_command_line = var.app_command_line

    # Pull images with the managed identity instead of stored credentials.
    container_registry_use_managed_identity = var.pull_with_managed_identity

    application_stack {
      docker_registry_url = var.container_registry_url
      docker_image_name   = var.container_image
    }

    # Inbound allow-list. When rules exist, App Service denies everything
    # that does not match, so this doubles as a default-deny when set.
    dynamic "ip_restriction" {
      for_each = { for i, cidr in var.allowed_inbound_ip_cidrs : i => cidr }
      content {
        action     = "Allow"
        ip_address = ip_restriction.value
        priority   = 1000 + ip_restriction.key
      }
    }
  }

  app_settings = local.app_settings

  # Sticky (slot-specific) settings: the App Insights wiring follows whichever
  # slot currently serves production across swaps.
  sticky_settings {
    app_setting_names = local.sticky_app_setting_names
  }
}

# Staging deployment slot: the standard rollout path is deploy-to-slot,
# verify, then swap. Changing the container image on the slot is how a new
# release enters the pipeline without touching production traffic.
resource "azurerm_linux_web_app_slot" "staging" {
  count = var.staging_slot_enabled ? 1 : 0

  name           = var.staging_slot_name
  app_service_id = azurerm_linux_web_app.this.id

  tags = local.common_tags

  identity {
    type = "SystemAssigned"
  }

  site_config {
    always_on                         = var.always_on
    health_check_path                 = var.health_check_path
    health_check_eviction_time_in_min = var.health_check_eviction_time_in_min
    http2_enabled                     = var.http2_enabled
    minimum_tls_version               = var.minimum_tls_version
    ftps_state                        = var.ftps_state

    app_command_line = var.app_command_line

    container_registry_use_managed_identity = var.pull_with_managed_identity

    application_stack {
      docker_registry_url = var.container_registry_url
      docker_image_name   = var.container_image
    }
  }

  app_settings = local.app_settings
}

# AcrPull grants when pulling images via managed identity.
resource "azurerm_role_assignment" "acr_pull" {
  for_each = local.acr_pull_principals

  scope                = var.container_registry_resource_id
  role_definition_name = "AcrPull"
  principal_id         = each.value
}
