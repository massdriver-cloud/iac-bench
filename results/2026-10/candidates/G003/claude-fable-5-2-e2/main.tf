###############################################################################
# Resource group & identity
###############################################################################

resource "azurerm_resource_group" "this" {
  count = local.create_resource_group ? 1 : 0

  name     = local.resource_group_name_static
  location = var.location
  tags     = local.tags
}

# One user-assigned identity shared by production and the staging slot. It
# exists before the app does, so registry and Key Vault access are in place on
# first start, and a release keeps the same identity when slots are swapped.
resource "azurerm_user_assigned_identity" "this" {
  name                = "id-${local.workload}"
  resource_group_name = local.resource_group_name
  location            = var.location
  tags                = local.tags
}

resource "azurerm_role_assignment" "acr_pull" {
  count = var.container_registry_id != null ? 1 : 0

  scope                = var.container_registry_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.this.principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "key_vault_secrets_user" {
  for_each = toset(var.key_vault_ids)

  scope                = each.value
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.this.principal_id
  principal_type       = "ServicePrincipal"
}

###############################################################################
# Capacity: plan + autoscale
###############################################################################

resource "azurerm_service_plan" "this" {
  name                = "asp-${local.workload}"
  resource_group_name = local.resource_group_name
  location            = var.location
  tags                = local.tags

  os_type                = "Linux"
  sku_name               = var.capacity.sku
  zone_balancing_enabled = var.capacity.zone_redundant

  # Initial size only. From then on the autoscale setting below owns the
  # instance count (including fixed-size deployments, where min == max), so an
  # apply never resets a plan that autoscale has scaled out.
  worker_count = var.capacity.min_instances

  lifecycle {
    ignore_changes = [worker_count]
  }
}

resource "azurerm_monitor_autoscale_setting" "this" {
  name                = "autoscale-${local.workload}"
  resource_group_name = local.resource_group_name
  location            = var.location
  tags                = local.tags
  target_resource_id  = azurerm_service_plan.this.id

  profile {
    name = "default"

    capacity {
      minimum = var.capacity.min_instances
      maximum = var.capacity.max_instances
      default = var.capacity.min_instances
    }

    # Rules only exist when there is room to scale; with min == max the
    # profile simply pins the instance count.
    dynamic "rule" {
      for_each = var.capacity.max_instances > var.capacity.min_instances ? [
        {
          metric    = "CpuPercentage"
          operator  = "GreaterThan"
          threshold = var.capacity.scale_out_cpu_percent
          window    = "PT10M"
          direction = "Increase"
          cooldown  = "PT5M"
        },
        {
          metric    = "MemoryPercentage"
          operator  = "GreaterThan"
          threshold = var.capacity.scale_out_memory_percent
          window    = "PT10M"
          direction = "Increase"
          cooldown  = "PT5M"
        },
        {
          metric    = "CpuPercentage"
          operator  = "LessThan"
          threshold = var.capacity.scale_in_cpu_percent
          window    = "PT15M"
          direction = "Decrease"
          cooldown  = "PT10M"
        },
      ] : []

      content {
        metric_trigger {
          metric_name        = rule.value.metric
          metric_namespace   = "microsoft.web/serverfarms"
          metric_resource_id = azurerm_service_plan.this.id
          time_grain         = "PT1M"
          statistic          = "Average"
          time_window        = rule.value.window
          time_aggregation   = "Average"
          operator           = rule.value.operator
          threshold          = rule.value.threshold
        }

        scale_action {
          direction = rule.value.direction
          type      = "ChangeCount"
          value     = "1"
          cooldown  = rule.value.cooldown
        }
      }
    }
  }
}

###############################################################################
# Production app
###############################################################################

resource "azurerm_linux_web_app" "this" {
  name                = local.app_name
  resource_group_name = local.resource_group_name
  location            = var.location
  tags                = local.tags
  service_plan_id     = azurerm_service_plan.this.id

  https_only                    = true
  client_affinity_enabled       = false
  public_network_access_enabled = local.public_network_access_enabled

  # With VNet integration, everything leaves through the VNet: application
  # traffic (vnet_route_all_enabled) and image pulls alike.
  virtual_network_subnet_id = var.vnet_integration_subnet_id
  vnet_image_pull_enabled   = var.vnet_integration_subnet_id != null

  # No publishing credentials: the only way to ship code is a container image.
  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = false

  key_vault_reference_identity_id = azurerm_user_assigned_identity.this.id

  identity {
    type         = "UserAssigned"
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
    always_on                = true
    http2_enabled            = true
    ftps_state               = "Disabled"
    minimum_tls_version      = "1.2"
    scm_minimum_tls_version  = "1.2"
    remote_debugging_enabled = false
    vnet_route_all_enabled   = var.vnet_integration_subnet_id != null

    health_check_path                 = var.health_check_path
    health_check_eviction_time_in_min = var.health_check_eviction_minutes

    container_registry_use_managed_identity       = local.registry_is_acr
    container_registry_managed_identity_client_id = local.registry_is_acr ? azurerm_user_assigned_identity.this.client_id : null

    ip_restriction_default_action     = local.ip_restriction_default_action
    scm_ip_restriction_default_action = local.ip_restriction_default_action
    scm_use_main_ip_restriction       = true

    application_stack {
      docker_registry_url = local.docker_registry_url
      docker_image_name   = local.docker_image_name
    }

    dynamic "ip_restriction" {
      for_each = local.ingress_rules

      content {
        name                      = ip_restriction.value.name
        priority                  = 100 + ip_restriction.key
        action                    = "Allow"
        ip_address                = ip_restriction.value.ip_address
        service_tag               = ip_restriction.value.service_tag
        virtual_network_subnet_id = ip_restriction.value.subnet_id

        dynamic "headers" {
          for_each = length(ip_restriction.value.fd_ids) > 0 ? [1] : []

          content {
            x_azure_fdid = ip_restriction.value.fd_ids
          }
        }
      }
    }
  }

  # Short-lived on-instance logs for `az webapp log tail`; durable logs go to
  # Log Analytics through the diagnostic settings.
  logs {
    detailed_error_messages = false
    failed_request_tracing  = false

    http_logs {
      file_system {
        retention_in_days = 3
        retention_in_mb   = 35
      }
    }
  }

  lifecycle {
    # Releases reach production by swapping the staging slot, never by editing
    # production in place. After the initial deployment the image running in
    # production is therefore whatever was last swapped in.
    ignore_changes = [
      site_config[0].application_stack[0].docker_image_name,
      site_config[0].application_stack[0].docker_registry_url,
    ]

    precondition {
      condition     = length(setintersection(keys(var.app_settings), keys(var.key_vault_secrets))) == 0
      error_message = "The same setting name appears in both app_settings and key_vault_secrets."
    }
  }

  depends_on = [
    azurerm_role_assignment.acr_pull,
    azurerm_role_assignment.key_vault_secrets_user,
  ]
}

###############################################################################
# Staging slot: where every new image lands first
###############################################################################

resource "azurerm_linux_web_app_slot" "staging" {
  name           = local.slot_name
  app_service_id = azurerm_linux_web_app.this.id
  tags           = local.tags

  https_only                    = true
  client_affinity_enabled       = false
  public_network_access_enabled = local.public_network_access_enabled

  virtual_network_subnet_id = var.vnet_integration_subnet_id
  vnet_image_pull_enabled   = var.vnet_integration_subnet_id != null

  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = false

  key_vault_reference_identity_id = azurerm_user_assigned_identity.this.id

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.this.id]
  }

  app_settings = local.app_settings

  site_config {
    always_on                = true
    http2_enabled            = true
    ftps_state               = "Disabled"
    minimum_tls_version      = "1.2"
    scm_minimum_tls_version  = "1.2"
    remote_debugging_enabled = false
    vnet_route_all_enabled   = var.vnet_integration_subnet_id != null

    health_check_path                 = var.health_check_path
    health_check_eviction_time_in_min = var.health_check_eviction_minutes

    container_registry_use_managed_identity       = local.registry_is_acr
    container_registry_managed_identity_client_id = local.registry_is_acr ? azurerm_user_assigned_identity.this.client_id : null

    ip_restriction_default_action     = local.ip_restriction_default_action
    scm_ip_restriction_default_action = local.ip_restriction_default_action
    scm_use_main_ip_restriction       = true

    application_stack {
      docker_registry_url = local.docker_registry_url
      docker_image_name   = local.docker_image_name
    }

    dynamic "ip_restriction" {
      for_each = local.ingress_rules

      content {
        name                      = ip_restriction.value.name
        priority                  = 100 + ip_restriction.key
        action                    = "Allow"
        ip_address                = ip_restriction.value.ip_address
        service_tag               = ip_restriction.value.service_tag
        virtual_network_subnet_id = ip_restriction.value.subnet_id

        dynamic "headers" {
          for_each = length(ip_restriction.value.fd_ids) > 0 ? [1] : []

          content {
            x_azure_fdid = ip_restriction.value.fd_ids
          }
        }
      }
    }
  }

  logs {
    detailed_error_messages = false
    failed_request_tracing  = false

    http_logs {
      file_system {
        retention_in_days = 3
        retention_in_mb   = 35
      }
    }
  }
}

###############################################################################
# Private endpoints (optional)
###############################################################################

resource "azurerm_private_endpoint" "app" {
  count = local.create_private_endpoints ? 1 : 0

  name                = "pe-${local.app_name}"
  resource_group_name = local.resource_group_name
  location            = var.location
  tags                = local.tags
  subnet_id           = var.ingress.private_endpoint_subnet_id

  private_service_connection {
    name                           = "psc-${local.app_name}"
    private_connection_resource_id = azurerm_linux_web_app.this.id
    subresource_names              = ["sites"]
    is_manual_connection           = false
  }

  dynamic "private_dns_zone_group" {
    for_each = length(var.ingress.private_dns_zone_ids) > 0 ? [1] : []

    content {
      name                 = "default"
      private_dns_zone_ids = var.ingress.private_dns_zone_ids
    }
  }
}

# The staging slot needs its own endpoint, otherwise a release cannot be
# verified before it is swapped into production.
resource "azurerm_private_endpoint" "staging" {
  count = local.create_private_endpoints ? 1 : 0

  name                = "pe-${local.app_name}-${local.slot_name}"
  resource_group_name = local.resource_group_name
  location            = var.location
  tags                = local.tags
  subnet_id           = var.ingress.private_endpoint_subnet_id

  private_service_connection {
    name                           = "psc-${local.app_name}-${local.slot_name}"
    private_connection_resource_id = azurerm_linux_web_app.this.id
    subresource_names              = ["sites-${local.slot_name}"]
    is_manual_connection           = false
  }

  dynamic "private_dns_zone_group" {
    for_each = length(var.ingress.private_dns_zone_ids) > 0 ? [1] : []

    content {
      name                 = "default"
      private_dns_zone_ids = var.ingress.private_dns_zone_ids
    }
  }

  # Serialise the two endpoint operations against the same site.
  depends_on = [
    azurerm_linux_web_app_slot.staging,
    azurerm_private_endpoint.app,
  ]
}
