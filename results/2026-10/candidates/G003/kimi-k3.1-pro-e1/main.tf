resource "azurerm_resource_group" "this" {
  count = var.create_resource_group ? 1 : 0

  name     = var.resource_group_name
  location = var.location
  tags     = local.tags
}

resource "azurerm_service_plan" "this" {
  name                   = local.plan_name
  resource_group_name    = local.resource_group_name
  location               = var.location
  os_type                = "Linux"
  sku_name               = var.service_plan_sku_name
  worker_count           = var.capacity
  zone_balancing_enabled = var.zone_balancing_enabled
  tags                   = local.tags

  # Azure Monitor, rather than a later OpenTofu refresh, owns live scale-out.
  lifecycle {
    ignore_changes = [worker_count]

    precondition {
      condition     = !var.autoscale_enabled || (var.autoscale_minimum_capacity <= var.capacity && var.capacity <= var.autoscale_maximum_capacity)
      error_message = "capacity must be between autoscale_minimum_capacity and autoscale_maximum_capacity when autoscaling is enabled."
    }

    precondition {
      condition     = !var.autoscale_enabled || var.autoscale_scale_in_cpu_percentage < var.autoscale_scale_out_cpu_percentage
      error_message = "autoscale_scale_in_cpu_percentage must be lower than autoscale_scale_out_cpu_percentage."
    }

    precondition {
      condition     = !var.zone_balancing_enabled || (var.capacity >= 3 && (!var.autoscale_enabled || var.autoscale_minimum_capacity >= 3))
      error_message = "Zone balancing requires capacity >= 3 and, when autoscaling, autoscale_minimum_capacity >= 3."
    }

    precondition {
      condition     = !var.deployment_slot_enabled || !contains(["B1", "B2", "B3"], upper(var.service_plan_sku_name))
      error_message = "Deployment slots require a Standard, Premium, or Isolated SKU; disable deployment_slot_enabled for Basic plans."
    }

    precondition {
      condition     = !var.autoscale_enabled || !contains(["B1", "B2", "B3"], upper(var.service_plan_sku_name))
      error_message = "Autoscaling requires a Standard, Premium, or Isolated SKU; disable autoscale_enabled for Basic plans."
    }
  }
}

resource "azurerm_user_assigned_identity" "this" {
  name                = local.identity_name
  resource_group_name = local.resource_group_name
  location            = var.location
  tags                = local.tags
}

resource "azurerm_role_assignment" "acr_pull" {
  count = var.container_registry_use_managed_identity && var.container_registry_id != null ? 1 : 0

  scope                = var.container_registry_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.this.principal_id
}

resource "azurerm_linux_web_app" "this" {
  name                = var.name
  resource_group_name = local.resource_group_name
  location            = var.location
  service_plan_id     = azurerm_service_plan.this.id

  app_settings                                   = local.production_app_settings
  client_affinity_enabled                        = false
  client_certificate_enabled                     = false
  enabled                                        = true
  ftp_publish_basic_authentication_enabled       = false
  https_only                                     = true
  key_vault_reference_identity_id                = azurerm_user_assigned_identity.this.id
  public_network_access_enabled                  = var.public_network_access_enabled
  virtual_network_subnet_id                      = var.virtual_network_subnet_id
  webdeploy_publish_basic_authentication_enabled = false
  tags                                           = local.tags

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.this.id]
  }

  site_config {
    always_on                                     = true
    app_command_line                              = var.container_start_command
    container_registry_use_managed_identity       = var.container_registry_use_managed_identity
    container_registry_managed_identity_client_id = var.container_registry_use_managed_identity ? azurerm_user_assigned_identity.this.client_id : null
    ftps_state                                    = "Disabled"
    health_check_path                             = var.health_check_path
    health_check_eviction_time_in_min             = var.health_check_eviction_time_in_min
    http2_enabled                                 = true
    ip_restriction_default_action                 = length(var.allowed_source_cidrs) > 0 ? "Deny" : "Allow"
    load_balancing_mode                           = "LeastRequests"
    minimum_tls_version                           = "1.2"
    remote_debugging_enabled                      = false
    scm_minimum_tls_version                       = "1.2"
    scm_use_main_ip_restriction                   = true
    use_32_bit_worker                             = false
    vnet_route_all_enabled                        = var.virtual_network_subnet_id != null
    websockets_enabled                            = false

    application_stack {
      docker_image_name        = var.container_image
      docker_registry_url      = var.container_registry_url
      docker_registry_username = var.container_registry_username
      docker_registry_password = var.container_registry_password
    }

    dynamic "ip_restriction" {
      for_each = var.allowed_source_cidrs
      content {
        name       = "allow-${ip_restriction.key}"
        action     = "Allow"
        priority   = 100 + ip_restriction.key
        ip_address = ip_restriction.value
      }
    }
  }

  dynamic "sticky_settings" {
    for_each = length(var.sticky_app_setting_names) > 0 ? [var.sticky_app_setting_names] : []
    content {
      app_setting_names = sticky_settings.value
    }
  }

  lifecycle {
    precondition {
      condition     = (var.container_registry_username == null) == (var.container_registry_password == null)
      error_message = "container_registry_username and container_registry_password must be supplied together."
    }

    precondition {
      condition     = !var.container_registry_use_managed_identity || var.container_registry_id != null
      error_message = "container_registry_id is required when container_registry_use_managed_identity is true so AcrPull can be assigned."
    }

    precondition {
      condition     = !var.container_registry_use_managed_identity || (var.container_registry_username == null && var.container_registry_password == null)
      error_message = "Use either ACR managed identity or registry username/password, not both."
    }

    precondition {
      condition     = length(var.private_dns_zone_ids) == 0 || var.private_endpoint_subnet_id != null
      error_message = "private_dns_zone_ids requires private_endpoint_subnet_id."
    }
  }

  depends_on = [azurerm_role_assignment.acr_pull]
}

resource "azurerm_linux_web_app_slot" "staging" {
  count = var.deployment_slot_enabled ? 1 : 0

  name           = var.deployment_slot_name
  app_service_id = azurerm_linux_web_app.this.id

  app_settings                                   = local.staging_app_settings
  client_affinity_enabled                        = false
  client_certificate_enabled                     = false
  enabled                                        = true
  ftp_publish_basic_authentication_enabled       = false
  https_only                                     = true
  key_vault_reference_identity_id                = azurerm_user_assigned_identity.this.id
  public_network_access_enabled                  = var.public_network_access_enabled
  virtual_network_subnet_id                      = var.virtual_network_subnet_id
  webdeploy_publish_basic_authentication_enabled = false
  tags                                           = local.tags

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.this.id]
  }

  site_config {
    always_on                                     = true
    app_command_line                              = var.container_start_command
    container_registry_use_managed_identity       = var.container_registry_use_managed_identity
    container_registry_managed_identity_client_id = var.container_registry_use_managed_identity ? azurerm_user_assigned_identity.this.client_id : null
    ftps_state                                    = "Disabled"
    health_check_path                             = var.health_check_path
    health_check_eviction_time_in_min             = var.health_check_eviction_time_in_min
    http2_enabled                                 = true
    ip_restriction_default_action                 = length(var.allowed_source_cidrs) > 0 ? "Deny" : "Allow"
    load_balancing_mode                           = "LeastRequests"
    minimum_tls_version                           = "1.2"
    remote_debugging_enabled                      = false
    scm_minimum_tls_version                       = "1.2"
    scm_use_main_ip_restriction                   = true
    use_32_bit_worker                             = false
    vnet_route_all_enabled                        = var.virtual_network_subnet_id != null
    websockets_enabled                            = false

    application_stack {
      docker_image_name        = local.staging_image
      docker_registry_url      = var.container_registry_url
      docker_registry_username = var.container_registry_username
      docker_registry_password = var.container_registry_password
    }

    dynamic "ip_restriction" {
      for_each = var.allowed_source_cidrs
      content {
        name       = "allow-${ip_restriction.key}"
        action     = "Allow"
        priority   = 100 + ip_restriction.key
        ip_address = ip_restriction.value
      }
    }
  }

  depends_on = [azurerm_role_assignment.acr_pull]
}

resource "azurerm_monitor_autoscale_setting" "this" {
  count = var.autoscale_enabled ? 1 : 0

  name                = local.autoscale_name
  resource_group_name = local.resource_group_name
  location            = var.location
  target_resource_id  = azurerm_service_plan.this.id
  enabled             = true
  tags                = local.tags

  profile {
    name = "cpu-baseline"

    capacity {
      default = var.capacity
      minimum = var.autoscale_minimum_capacity
      maximum = var.autoscale_maximum_capacity
    }

    rule {
      metric_trigger {
        metric_name        = "CpuPercentage"
        metric_namespace   = "Microsoft.Web/serverfarms"
        metric_resource_id = azurerm_service_plan.this.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT10M"
        time_aggregation   = "Average"
        operator           = "GreaterThan"
        threshold          = var.autoscale_scale_out_cpu_percentage
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
        metric_namespace   = "Microsoft.Web/serverfarms"
        metric_resource_id = azurerm_service_plan.this.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT15M"
        time_aggregation   = "Average"
        operator           = "LessThan"
        threshold          = var.autoscale_scale_in_cpu_percentage
      }

      scale_action {
        direction = "Decrease"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT10M"
      }
    }
  }

  dynamic "notification" {
    for_each = length(var.alert_email_receivers) > 0 ? [var.alert_email_receivers] : []
    content {
      email {
        send_to_subscription_administrator    = false
        send_to_subscription_co_administrator = false
        custom_emails                         = notification.value
      }
    }
  }
}
