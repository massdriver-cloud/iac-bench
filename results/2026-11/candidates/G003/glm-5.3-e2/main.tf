# ---------------------------------------------------------------------------
# Resource group
# ---------------------------------------------------------------------------

resource "azurerm_resource_group" "this" {
  name     = "${local.name_prefix}-rg"
  location = var.location
  tags     = local.common_tags
}

# ---------------------------------------------------------------------------
# App Service plan (capacity + availability)
#
# Premium v3 is used exclusively: it is the family that guarantees containers,
# always-on, deployment slots, autoscaling, and zone redundancy. On current
# Azure, Premium v3 plans in zone-capable regions are zone-redundant by
# platform default, which is why the plan below never configures it: the
# min_instances floor keeps one instance per zone warm.
# ---------------------------------------------------------------------------

resource "azurerm_service_plan" "this" {
  name                = "${local.name_prefix}-plan"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  os_type             = "Linux"
  sku_name            = local.sku_by_size[var.instance_size]
  worker_count        = var.min_instances
  tags                = local.common_tags

  lifecycle {
    # The autoscale setting below is the source of truth for instance count
    # after creation: Azure Monitor scales the plan and OpenTofu must not
    # fight it. worker_count only sets the initial (minimum) capacity.
    ignore_changes = [worker_count]

    precondition {
      condition     = var.max_instances >= var.min_instances
      error_message = "max_instances must be greater than or equal to min_instances."
    }
  }
}

# ---------------------------------------------------------------------------
# The web app (health + the application)
# ---------------------------------------------------------------------------

resource "azurerm_linux_web_app" "this" {
  name                      = local.name_prefix
  resource_group_name       = azurerm_resource_group.this.name
  location                  = azurerm_resource_group.this.location
  service_plan_id           = azurerm_service_plan.this.id
  https_only                = true
  virtual_network_subnet_id = var.virtual_network_subnet_id
  tags                      = local.common_tags

  # Publishing for this module's apps goes through container images and the
  # staging slot, never FTP/WebDeploy, so their basic-auth logins stay off.
  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = false

  identity {
    type = "SystemAssigned"
  }

  site_config {
    always_on                         = true
    health_check_path                 = var.health_probe_path
    health_check_eviction_time_in_min = 10
    http2_enabled                     = true
    minimum_tls_version               = "1.2"
    ftps_state                        = "Disabled"
    load_balancing_mode               = "LeastRequests"

    application_stack {
      docker_image_name = "${var.container_image}:${var.container_image_tag}"
    }
  }

  app_settings = local.app_settings

  logs {
    application_logs {
      file_system_level = "Information"
    }

    http_logs {
      file_system {
        retention_in_days = 7
        retention_in_mb   = 35
      }
    }
  }
}

# ---------------------------------------------------------------------------
# Staging slot (rollouts)
# ---------------------------------------------------------------------------

resource "azurerm_linux_web_app_slot" "staging" {
  count = var.enable_staging_slot ? 1 : 0

  name                      = "staging"
  app_service_id            = azurerm_linux_web_app.this.id
  https_only                = true
  virtual_network_subnet_id = var.virtual_network_subnet_id
  tags                      = local.common_tags

  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = false

  identity {
    type = "SystemAssigned"
  }

  site_config {
    always_on                         = true
    health_check_path                 = var.health_probe_path
    health_check_eviction_time_in_min = 10
    http2_enabled                     = true
    minimum_tls_version               = "1.2"
    ftps_state                        = "Disabled"
    load_balancing_mode               = "LeastRequests"
    auto_swap_slot_name               = var.staging_auto_swap ? "production" : null

    application_stack {
      docker_image_name = "${var.container_image}:${var.container_image_tag}"
    }
  }

  app_settings = local.app_settings

  logs {
    application_logs {
      file_system_level = "Information"
    }

    http_logs {
      file_system {
        retention_in_days = 7
        retention_in_mb   = 35
      }
    }
  }

  lifecycle {
    # The image running on staging is owned by the delivery pipeline: it deploys
    # the candidate build there before promoting it. Everything else about the
    # slot (settings, health, identity, networking) stays module-managed so a
    # swap is always safe.
    ignore_changes = [
      site_config[0].application_stack[0].docker_image_name,
    ]
  }
}
