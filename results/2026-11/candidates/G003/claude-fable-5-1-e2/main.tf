locals {
  # ---- image reference parsing -------------------------------------------
  # "myacr.azurecr.io/team/api:1.2.3" -> host "myacr.azurecr.io", image "team/api:1.2.3"
  # "nginx:1.25"                       -> host Docker Hub,         image "nginx:1.25"
  image_parts      = split("/", var.container_image)
  image_first_part = local.image_parts[0]
  image_has_host   = length(local.image_parts) > 1 && (can(regex("[.:]", local.image_first_part)) || local.image_first_part == "localhost")
  registry_host    = local.image_has_host ? local.image_first_part : "index.docker.io"
  registry_url     = "https://${local.registry_host}"
  docker_image     = local.image_has_host ? join("/", slice(local.image_parts, 1, length(local.image_parts))) : var.container_image

  use_acr_identity = var.container_registry_id != null

  # ---- capacity ----------------------------------------------------------
  autoscale_enabled = var.max_instances > var.min_instances
  sku_tier          = substr(var.sku_name, 0, 1) # B / S / P
  slot_supported    = contains(["S", "P"], local.sku_tier)
  staging_slot      = var.staging_slot_enabled && local.slot_supported

  # ---- app settings ------------------------------------------------------
  managed_app_settings = {
    WEBSITES_PORT                              = tostring(var.container_port)
    WEBSITES_ENABLE_APP_SERVICE_STORAGE        = "false"
    WEBSITES_CONTAINER_START_TIME_LIMIT        = "600"
    WEBSITE_HEALTHCHECK_MAXPINGFAILURES        = "10"
    DOCKER_ENABLE_CI                           = "false"
    APPLICATIONINSIGHTS_CONNECTION_STRING      = azurerm_application_insights.this.connection_string
    ApplicationInsightsAgent_EXTENSION_VERSION = "~3"
    XDT_MicrosoftApplicationInsights_Mode      = "recommended"
  }
  app_settings = merge(var.app_settings, local.managed_app_settings)

  # ---- access restrictions ----------------------------------------------
  ip_rules = [
    for idx, cidr in var.allowed_ip_ranges : {
      name        = "allow-ip-${idx}"
      priority    = 100 + idx
      ip_address  = cidr
      service_tag = null
    }
  ]
  tag_rules = [
    for idx, tag in var.allowed_service_tags : {
      name        = "allow-tag-${idx}"
      priority    = 200 + idx
      ip_address  = null
      service_tag = tag
    }
  ]
  access_rules = concat(local.ip_rules, local.tag_rules)

  tags = merge(var.tags, { "managed-by" = "opentofu", "service" = var.name })
}

# ---------------------------------------------------------------------------
# Guard rails
# ---------------------------------------------------------------------------

check "zone_redundancy_requirements" {
  assert {
    condition     = !var.zone_redundant || (local.sku_tier == "P" && var.min_instances >= 3)
    error_message = "zone_redundant requires a Premium v3 SKU and min_instances >= 3."
  }
}

check "autoscale_bounds" {
  assert {
    condition     = var.max_instances >= var.min_instances
    error_message = "max_instances must be >= min_instances."
  }
}

check "staging_slot_sku" {
  assert {
    condition     = !var.staging_slot_enabled || local.slot_supported
    error_message = "Deployment slots require a Standard or Premium SKU; staging slot will not be created on Basic."
  }
}

# ---------------------------------------------------------------------------
# Resource group
# ---------------------------------------------------------------------------

resource "azurerm_resource_group" "this" {
  name     = "rg-${var.name}"
  location = var.location
  tags     = local.tags
}

# ---------------------------------------------------------------------------
# Identity
# ---------------------------------------------------------------------------

resource "azurerm_user_assigned_identity" "this" {
  name                = "id-${var.name}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.tags
}

resource "azurerm_role_assignment" "acr_pull" {
  count = local.use_acr_identity ? 1 : 0

  scope                = var.container_registry_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.this.principal_id
}

# ---------------------------------------------------------------------------
# Plan
# ---------------------------------------------------------------------------

resource "azurerm_service_plan" "this" {
  name                   = "asp-${var.name}"
  location               = azurerm_resource_group.this.location
  resource_group_name    = azurerm_resource_group.this.name
  os_type                = "Linux"
  sku_name               = var.sku_name
  worker_count           = var.min_instances
  zone_balancing_enabled = var.zone_redundant
  tags                   = local.tags

  lifecycle {
    # Autoscale owns the live instance count once it is enabled.
    ignore_changes = [worker_count]
  }
}

# ---------------------------------------------------------------------------
# Web app (production)
# ---------------------------------------------------------------------------

resource "azurerm_linux_web_app" "this" {
  name                = var.name
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  service_plan_id     = azurerm_service_plan.this.id
  tags                = local.tags

  https_only                                     = true
  client_affinity_enabled                        = false
  public_network_access_enabled                  = true
  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = false
  virtual_network_subnet_id                      = var.virtual_network_subnet_id

  identity {
    type         = "SystemAssigned, UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.this.id]
  }

  app_settings = local.app_settings

  dynamic "sticky_settings" {
    for_each = length(var.sticky_app_setting_names) > 0 ? [1] : []
    content {
      app_setting_names = var.sticky_app_setting_names
    }
  }

  site_config {
    always_on                                     = true
    http2_enabled                                 = true
    minimum_tls_version                           = "1.2"
    ftps_state                                    = "Disabled"
    health_check_path                             = var.health_check_path
    health_check_eviction_time_in_min             = var.health_check_eviction_time_in_min
    container_registry_use_managed_identity       = local.use_acr_identity
    container_registry_managed_identity_client_id = local.use_acr_identity ? azurerm_user_assigned_identity.this.client_id : null
    vnet_route_all_enabled                        = var.virtual_network_subnet_id != null
    ip_restriction_default_action                 = length(local.access_rules) > 0 ? "Deny" : "Allow"

    application_stack {
      docker_image_name        = local.docker_image
      docker_registry_url      = local.registry_url
      docker_registry_username = var.registry_username
      docker_registry_password = var.registry_password
    }

    dynamic "ip_restriction" {
      for_each = local.access_rules
      content {
        name        = ip_restriction.value.name
        priority    = ip_restriction.value.priority
        action      = "Allow"
        ip_address  = ip_restriction.value.ip_address
        service_tag = ip_restriction.value.service_tag
      }
    }
  }

  logs {
    detailed_error_messages = true
    failed_request_tracing  = true

    application_logs {
      file_system_level = "Information"
    }

    http_logs {
      file_system {
        retention_in_days = 7
        retention_in_mb   = 100
      }
    }
  }

  lifecycle {
    # The running image is owned by the deployment pipeline (deploy to the
    # staging slot, verify, swap). Tofu sets the initial image only.
    ignore_changes = [
      site_config[0].application_stack[0].docker_image_name,
    ]
  }

  depends_on = [azurerm_role_assignment.acr_pull]
}

# ---------------------------------------------------------------------------
# Staging slot (rollouts)
# ---------------------------------------------------------------------------

resource "azurerm_linux_web_app_slot" "staging" {
  count = local.staging_slot ? 1 : 0

  name           = "staging"
  app_service_id = azurerm_linux_web_app.this.id
  tags           = local.tags

  https_only                                     = true
  client_affinity_enabled                        = false
  public_network_access_enabled                  = true
  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = false
  virtual_network_subnet_id                      = var.virtual_network_subnet_id

  identity {
    type         = "SystemAssigned, UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.this.id]
  }

  app_settings = local.app_settings

  site_config {
    always_on                                     = true
    http2_enabled                                 = true
    minimum_tls_version                           = "1.2"
    ftps_state                                    = "Disabled"
    health_check_path                             = var.health_check_path
    health_check_eviction_time_in_min             = var.health_check_eviction_time_in_min
    container_registry_use_managed_identity       = local.use_acr_identity
    container_registry_managed_identity_client_id = local.use_acr_identity ? azurerm_user_assigned_identity.this.client_id : null
    vnet_route_all_enabled                        = var.virtual_network_subnet_id != null
    ip_restriction_default_action                 = length(local.access_rules) > 0 ? "Deny" : "Allow"

    application_stack {
      docker_image_name        = local.docker_image
      docker_registry_url      = local.registry_url
      docker_registry_username = var.registry_username
      docker_registry_password = var.registry_password
    }

    dynamic "ip_restriction" {
      for_each = local.access_rules
      content {
        name        = ip_restriction.value.name
        priority    = ip_restriction.value.priority
        action      = "Allow"
        ip_address  = ip_restriction.value.ip_address
        service_tag = ip_restriction.value.service_tag
      }
    }
  }

  logs {
    detailed_error_messages = true
    failed_request_tracing  = true

    application_logs {
      file_system_level = "Information"
    }

    http_logs {
      file_system {
        retention_in_days = 7
        retention_in_mb   = 100
      }
    }
  }

  lifecycle {
    ignore_changes = [
      site_config[0].application_stack[0].docker_image_name,
    ]
  }
}

# ---------------------------------------------------------------------------
# Autoscale (capacity)
# ---------------------------------------------------------------------------

resource "azurerm_monitor_autoscale_setting" "this" {
  count = local.autoscale_enabled ? 1 : 0

  name                = "autoscale-${var.name}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  target_resource_id  = azurerm_service_plan.this.id
  enabled             = true
  tags                = local.tags

  profile {
    name = "default"

    capacity {
      default = var.min_instances
      minimum = var.min_instances
      maximum = var.max_instances
    }

    rule {
      metric_trigger {
        metric_name        = "CpuPercentage"
        metric_resource_id = azurerm_service_plan.this.id
        metric_namespace   = "microsoft.web/serverfarms"
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT10M"
        time_aggregation   = "Average"
        operator           = "GreaterThan"
        threshold          = var.autoscale_cpu_scale_out_percent
      }
      scale_action {
        direction = "Increase"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT5M"
      }
    }

    rule {
      metric_trigger {
        metric_name        = "CpuPercentage"
        metric_resource_id = azurerm_service_plan.this.id
        metric_namespace   = "microsoft.web/serverfarms"
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT10M"
        time_aggregation   = "Average"
        operator           = "LessThan"
        threshold          = var.autoscale_cpu_scale_in_percent
      }
      scale_action {
        direction = "Decrease"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT10M"
      }
    }
  }

  notification {
    email {
      send_to_subscription_administrator    = false
      send_to_subscription_co_administrator = false
      custom_emails                         = var.alert_email_addresses
    }
  }
}
