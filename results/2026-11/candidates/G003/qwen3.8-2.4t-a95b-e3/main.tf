# ---------------------------------------------------------------------------
# Resource group
# ---------------------------------------------------------------------------
# Every service gets its own resource group: a clean blast radius, trivial
# ownership attribution, and a clean teardown (destroy removes everything
# this module created).

resource "azurerm_resource_group" "this" {
  name     = local.names.resource_group
  location = var.location
  tags     = local.tags
}

# ---------------------------------------------------------------------------
# Capacity: App Service Plan
# ---------------------------------------------------------------------------
# One plan per service so a noisy neighbour can never starve another team's
# workloads. SKU, instance floor and zone balancing encode the capacity and
# availability posture; autoscale (see autoscale.tf) rides on top.

resource "azurerm_service_plan" "this" {
  name                = local.names.service_plan
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name

  os_type      = "Linux"
  sku_name     = var.sku_name
  worker_count = local.minimum_instances

  # Spread instances across availability zones. In this provider version the
  # property is named zone_balancing_enabled; the 3-instance floor applied to
  # worker_count above keeps the plan valid in this mode.
  zone_balancing_enabled = var.zone_redundant

  tags = local.tags
}

# ---------------------------------------------------------------------------
# The service: Linux web app running the team's container image
# ---------------------------------------------------------------------------

resource "azurerm_linux_web_app" "this" {
  name                = local.names.app
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  service_plan_id     = azurerm_service_plan.this.id

  https_only                    = var.https_only
  public_network_access_enabled = var.public_network_access_enabled
  virtual_network_subnet_id     = var.virtual_network_subnet_id

  # HTTP APIs are stateless; session affinity only pins users to instances
  # that may be recycled, so keep it off.
  client_affinity_enabled = false

  # Images arrive from a container registry, never over password-based
  # publishing endpoints.
  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = false

  dynamic "identity" {
    for_each = var.managed_identity_enabled ? ["SystemAssigned"] : []

    content {
      type = identity.value
    }
  }

  site_config {
    always_on           = var.always_on
    http2_enabled       = true
    minimum_tls_version = "1.2"
    # Containers are deployed from a registry; FTP(S) publishing has no
    # business being reachable.
    ftps_state = "Disabled"

    vnet_route_all_enabled = var.virtual_network_subnet_id != null

    # Health: the platform probes each instance on this path and replaces
    # instances that stop answering, without anyone carrying a pager. The
    # feature is active when a path is set (health_check_enabled = false
    # clears it).
    health_check_path                 = var.health_check_enabled ? var.health_check_path : null
    health_check_eviction_time_in_min = var.health_check_enabled ? var.health_check_eviction_time_in_min : null

    app_command_line = var.app_command_line

    application_stack {
      docker_image_name   = var.container_image
      docker_registry_url = var.container_registry_url
    }
  }

  app_settings = local.app_settings

  tags = local.tags
}

# ---------------------------------------------------------------------------
# Rollouts: deployment slot
# ---------------------------------------------------------------------------
# The standard rollout path: publish the next image tag to the staging slot,
# smoke-test it against real infrastructure, then swap it into production.
# The slot runs on the same plan and gets the same hardened configuration.

resource "azurerm_linux_web_app_slot" "staging" {
  count = var.staging_slot_enabled ? 1 : 0

  name           = var.staging_slot_name
  app_service_id = azurerm_linux_web_app.this.id

  # The slot is production traffic in waiting: same security posture.
  https_only                    = var.https_only
  public_network_access_enabled = var.public_network_access_enabled

  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = false

  dynamic "identity" {
    for_each = var.managed_identity_enabled ? ["SystemAssigned"] : []

    content {
      type = identity.value
    }
  }

  site_config {
    always_on           = var.always_on
    http2_enabled       = true
    minimum_tls_version = "1.2"
    ftps_state          = "Disabled"

    vnet_route_all_enabled = var.virtual_network_subnet_id != null

    health_check_path                 = var.health_check_enabled ? var.health_check_path : null
    health_check_eviction_time_in_min = var.health_check_enabled ? var.health_check_eviction_time_in_min : null

    app_command_line = var.app_command_line

    application_stack {
      docker_image_name   = var.container_image
      docker_registry_url = var.container_registry_url
    }
  }

  app_settings = local.app_settings

  tags = local.tags
}

# ---------------------------------------------------------------------------
# Operations guardrail
# ---------------------------------------------------------------------------
# Production services are torn down through this module, never through a stray
# portal click. The lock still allows updates (including slot swaps).

resource "azurerm_management_lock" "app" {
  count = var.management_lock_enabled ? 1 : 0

  name       = local.names.lock_app
  scope      = azurerm_linux_web_app.this.id
  lock_level = "CanNotDelete"
  notes      = "Standard SRE guardrail: manage this app through its OpenTofu module. Set management_lock_enabled = false to remove."
}
