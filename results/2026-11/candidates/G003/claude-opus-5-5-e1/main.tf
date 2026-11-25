locals {
  create_rg           = var.resource_group_name == null
  resource_group_name = local.create_rg ? azurerm_resource_group.this[0].name : var.resource_group_name

  create_workspace = var.log_analytics_workspace_id == null
  workspace_id     = local.create_workspace ? azurerm_log_analytics_workspace.this[0].id : var.log_analytics_workspace_id

  autoscale_enabled = var.max_instances > var.min_instances
  use_mi_pull       = var.container_registry_use_managed_identity || var.acr_id != null

  staging_image = coalesce(var.staging_container_image, var.container_image)

  tags = merge(var.tags, { service = var.name, managed-by = "opentofu" })

  restricted = length(var.allowed_ip_cidrs) > 0

  # Settings the module owns; they override user-provided keys.
  platform_app_settings = {
    WEBSITES_PORT                         = tostring(var.container_port)
    WEBSITES_ENABLE_APP_SERVICE_STORAGE   = "false"
    WEBSITES_CONTAINER_START_TIME_LIMIT   = "600"
    APPLICATIONINSIGHTS_CONNECTION_STRING = azurerm_application_insights.this.connection_string
  }

  app_settings = merge(var.app_settings, var.sensitive_app_settings, local.platform_app_settings)

  ip_restrictions = [for i, cidr in var.allowed_ip_cidrs : {
    name     = "allow-${i}"
    cidr     = cidr
    priority = 100 + i
  }]
}

resource "azurerm_resource_group" "this" {
  count    = local.create_rg ? 1 : 0
  name     = "rg-${var.name}"
  location = var.location
  tags     = local.tags
}

# ---------------------------------------------------------------------------
# Observability backends
# ---------------------------------------------------------------------------
resource "azurerm_log_analytics_workspace" "this" {
  count               = local.create_workspace ? 1 : 0
  name                = "log-${var.name}"
  location            = var.location
  resource_group_name = local.resource_group_name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days
  tags                = local.tags
}

resource "azurerm_application_insights" "this" {
  name                = "appi-${var.name}"
  location            = var.location
  resource_group_name = local.resource_group_name
  workspace_id        = local.workspace_id
  application_type    = "web"
  tags                = local.tags
}

# ---------------------------------------------------------------------------
# Compute
# ---------------------------------------------------------------------------
resource "azurerm_service_plan" "this" {
  name                   = "asp-${var.name}"
  location               = var.location
  resource_group_name    = local.resource_group_name
  os_type                = "Linux"
  sku_name               = var.sku_name
  worker_count           = var.min_instances
  zone_balancing_enabled = var.zone_redundant
  tags                   = local.tags

  lifecycle {
    # Autoscale owns the live instance count once deployed.
    ignore_changes = [worker_count]

    precondition {
      condition     = !var.zone_redundant || (can(regex("^(P|I)", var.sku_name)) && var.min_instances >= 2)
      error_message = "zone_redundant requires a Premium or Isolated SKU and min_instances >= 2."
    }
    precondition {
      condition     = var.max_instances >= var.min_instances
      error_message = "max_instances must be >= min_instances."
    }
  }
}

resource "azurerm_linux_web_app" "this" {
  name                                           = var.name
  location                                       = var.location
  resource_group_name                            = local.resource_group_name
  service_plan_id                                = azurerm_service_plan.this.id
  https_only                                     = true
  client_affinity_enabled                        = false
  public_network_access_enabled                  = true
  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = false
  virtual_network_subnet_id                      = var.vnet_integration_subnet_id
  tags                                           = local.tags

  identity {
    type = "SystemAssigned"
  }

  app_settings = local.app_settings

  site_config {
    always_on                               = true
    http2_enabled                           = true
    minimum_tls_version                     = "1.2"
    scm_minimum_tls_version                 = "1.2"
    ftps_state                              = "Disabled"
    health_check_path                       = var.health_check_path
    health_check_eviction_time_in_min       = var.health_check_eviction_minutes
    container_registry_use_managed_identity = local.use_mi_pull
    vnet_route_all_enabled                  = var.vnet_integration_subnet_id != null
    ip_restriction_default_action           = local.restricted ? "Deny" : "Allow"
    scm_ip_restriction_default_action       = local.restricted ? "Deny" : "Allow"
    scm_use_main_ip_restriction             = true

    application_stack {
      docker_image_name   = var.container_image
      docker_registry_url = var.container_registry_url
    }

    dynamic "ip_restriction" {
      for_each = local.ip_restrictions
      content {
        name       = ip_restriction.value.name
        ip_address = ip_restriction.value.cidr
        priority   = ip_restriction.value.priority
        action     = "Allow"
      }
    }
  }

  logs {
    detailed_error_messages = true
    failed_request_tracing  = true

    http_logs {
      file_system {
        retention_in_days = 7
        retention_in_mb   = 35
      }
    }
  }
}

# Blue/green: deploy to staging, verify via staging_url (same health check),
# then swap (see output swap_command). Runs on the same plan/instances.
resource "azurerm_linux_web_app_slot" "staging" {
  count                                          = var.enable_staging_slot ? 1 : 0
  name                                           = "staging"
  app_service_id                                 = azurerm_linux_web_app.this.id
  https_only                                     = true
  client_affinity_enabled                        = false
  public_network_access_enabled                  = true
  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = false
  virtual_network_subnet_id                      = var.vnet_integration_subnet_id
  tags                                           = local.tags

  identity {
    type = "SystemAssigned"
  }

  app_settings = local.app_settings

  site_config {
    always_on                               = true
    http2_enabled                           = true
    minimum_tls_version                     = "1.2"
    scm_minimum_tls_version                 = "1.2"
    ftps_state                              = "Disabled"
    health_check_path                       = var.health_check_path
    health_check_eviction_time_in_min       = var.health_check_eviction_minutes
    container_registry_use_managed_identity = local.use_mi_pull
    vnet_route_all_enabled                  = var.vnet_integration_subnet_id != null
    ip_restriction_default_action           = local.restricted ? "Deny" : "Allow"
    scm_ip_restriction_default_action       = local.restricted ? "Deny" : "Allow"
    scm_use_main_ip_restriction             = true

    application_stack {
      docker_image_name   = local.staging_image
      docker_registry_url = var.container_registry_url
    }

    dynamic "ip_restriction" {
      for_each = local.ip_restrictions
      content {
        name       = ip_restriction.value.name
        ip_address = ip_restriction.value.cidr
        priority   = ip_restriction.value.priority
        action     = "Allow"
      }
    }
  }
}

resource "azurerm_role_assignment" "acr_pull" {
  count                = var.acr_id != null ? 1 : 0
  scope                = var.acr_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_linux_web_app.this.identity[0].principal_id
}

resource "azurerm_role_assignment" "acr_pull_staging" {
  count                = var.acr_id != null && var.enable_staging_slot ? 1 : 0
  scope                = var.acr_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_linux_web_app_slot.staging[0].identity[0].principal_id
}
