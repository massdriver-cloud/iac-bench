locals {
  # Derive the tier family from the SKU so the module can gracefully drop
  # features a tier cannot do (slots, autoscale, always-on, health checks)
  # instead of failing at apply time.
  sku_prefix = upper(substr(var.sku_name, 0, 1))
  sku_tier = (
    local.sku_prefix == "F" ? "Free" :
    local.sku_prefix == "D" ? "Shared" :
    local.sku_prefix == "B" ? "Basic" :
    local.sku_prefix == "S" ? "Standard" :
    local.sku_prefix == "P" ? (length(regexall("(?i)v2$", var.sku_name)) > 0 ? "PremiumV2" : "PremiumV3") :
    local.sku_prefix == "I" ? "Isolated" :
    "Unknown"
  )

  free_or_shared = contains(["Free", "Shared"], local.sku_tier)

  sku_supports_slots        = !contains(["Free", "Shared", "Basic", "Unknown"], local.sku_tier)
  sku_supports_autoscale    = !contains(["Free", "Shared", "Basic", "Unknown"], local.sku_tier)
  sku_supports_zones        = contains(["PremiumV2", "PremiumV3"], local.sku_tier)
  sku_supports_health_check = !local.free_or_shared

  slot_enabled      = var.staging_slot_enabled && local.sku_supports_slots
  autoscale_enabled = var.autoscale_enabled && local.sku_supports_autoscale
  always_on         = var.always_on && !local.free_or_shared

  # azurewebsites.net hostnames are global; a short suffix keeps applies
  # collision-free while staying recognisable.
  web_app_name = coalesce(var.web_app_name, "${var.name}-${random_string.suffix.result}")

  tags = merge({
    "service"    = var.name
    "managed-by" = "opentofu"
    "module"     = "app-service-standard"
  }, var.tags)
}

resource "random_string" "suffix" {
  length  = 6
  upper   = false
  special = false
}

resource "azurerm_resource_group" "this" {
  name     = var.resource_group_name
  location = var.location
  tags     = local.tags
}

resource "azurerm_service_plan" "this" {
  name                = "${var.name}-plan"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location

  os_type                = "Linux"
  sku_name               = var.sku_name
  worker_count           = var.instance_count
  zone_balancing_enabled = var.zone_redundant

  tags = local.tags

  lifecycle {
    precondition {
      condition     = !var.zone_redundant || (local.sku_supports_zones && var.instance_count >= 3)
      error_message = "zone_redundant requires a Premium v2/v3 SKU and instance_count >= 3."
    }
  }
}

resource "azurerm_linux_web_app" "this" {
  name                = local.web_app_name
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  service_plan_id     = azurerm_service_plan.this.id

  https_only                    = true
  public_network_access_enabled = true
  client_affinity_enabled       = false # stateless APIs; ARR affinity only hurts load distribution
  virtual_network_subnet_id     = var.vnet_integration_subnet_id

  # Container workloads deploy by swapping the image, not via FTP/WebDeploy
  # publish profiles, so basic-auth publishing endpoints stay closed.
  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = false

  app_settings = merge(local.default_app_settings, var.app_settings)

  identity {
    type = "SystemAssigned"
  }

  site_config {
    always_on                         = local.always_on
    http2_enabled                     = true
    minimum_tls_version               = "1.2"
    ftps_state                        = "Disabled"
    health_check_path                 = local.sku_supports_health_check ? var.health_check_path : null
    health_check_eviction_time_in_min = local.sku_supports_health_check ? var.health_check_eviction_time_in_min : null
    vnet_route_all_enabled            = var.vnet_route_all_enabled

    container_registry_use_managed_identity = var.container_registry_id != null

    application_stack {
      docker_image_name   = var.container_image
      docker_registry_url = var.container_registry_url
    }

    # Auto-heal is enabled by the presence of this block: recycle the worker
    # when it serves a sustained burst of 5xx within 5 minutes.
    dynamic "auto_heal_setting" {
      for_each = var.auto_heal_enabled ? [1] : []

      content {
        action {
          action_type                    = "Recycle"
          minimum_process_execution_time = "00:01:00"
        }

        trigger {
          status_code {
            count             = var.auto_heal_status_code_count
            interval          = "00:05:00"
            status_code_range = "500-599"
          }
        }
      }
    }
  }

  logs {
    detailed_error_messages = true
    failed_request_tracing  = true

    application_logs {
      file_system_level = var.app_log_level
    }

    http_logs {
      file_system {
        retention_in_days = var.http_log_retention_days
        retention_in_mb   = 35
      }
    }
  }

  tags = local.tags

  # The pipeline owns the running image (deploy to slot, smoke test, swap).
  # Terraform owns the infrastructure, so a later apply must not roll the
  # app back to whatever image was current when the module was first run.
  lifecycle {
    ignore_changes = [
      site_config[0].application_stack[0].docker_image_name,
    ]
  }
}

resource "azurerm_linux_web_app_slot" "staging" {
  count = local.slot_enabled ? 1 : 0

  name           = var.staging_slot_name
  app_service_id = azurerm_linux_web_app.this.id

  https_only                    = true
  public_network_access_enabled = true
  client_affinity_enabled       = false
  virtual_network_subnet_id     = var.vnet_integration_subnet_id

  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = false

  app_settings = merge(local.default_app_settings, var.app_settings)

  identity {
    type = "SystemAssigned"
  }

  site_config {
    always_on                         = local.always_on
    http2_enabled                     = true
    minimum_tls_version               = "1.2"
    ftps_state                        = "Disabled"
    health_check_path                 = local.sku_supports_health_check ? var.health_check_path : null
    health_check_eviction_time_in_min = local.sku_supports_health_check ? var.health_check_eviction_time_in_min : null
    vnet_route_all_enabled            = var.vnet_route_all_enabled

    container_registry_use_managed_identity = var.container_registry_id != null

    application_stack {
      docker_image_name   = var.container_image
      docker_registry_url = var.container_registry_url
    }
  }

  logs {
    detailed_error_messages = true
    failed_request_tracing  = true

    application_logs {
      file_system_level = var.app_log_level
    }

    http_logs {
      file_system {
        retention_in_days = var.http_log_retention_days
        retention_in_mb   = 35
      }
    }
  }

  tags = local.tags

  lifecycle {
    ignore_changes = [
      site_config[0].application_stack[0].docker_image_name,
    ]
  }
}

# Private ACR pulls use the app's managed identity; no registry passwords
# in state. Both the app and the slot get their own grant.
resource "azurerm_role_assignment" "acr_pull" {
  count = var.container_registry_id != null ? 1 : 0

  scope                = var.container_registry_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_linux_web_app.this.identity[0].principal_id
}

resource "azurerm_role_assignment" "acr_pull_staging" {
  count = var.container_registry_id != null && local.slot_enabled ? 1 : 0

  scope                = var.container_registry_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_linux_web_app_slot.staging[0].identity[0].principal_id
}
