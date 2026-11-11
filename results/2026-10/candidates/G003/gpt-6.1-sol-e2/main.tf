locals {
  settings = merge(var.app_settings, {
    WEBSITES_PORT                         = tostring(var.container_port)
    WEBSITES_ENABLE_APP_SERVICE_STORAGE   = "false"
    APPLICATIONINSIGHTS_CONNECTION_STRING = azurerm_application_insights.this.connection_string
  })
}

resource "azurerm_resource_group" "this" {
  name     = "${var.name}-rg"
  location = var.location
  tags     = var.tags
}

resource "azurerm_service_plan" "this" {
  name                   = "${var.name}-plan"
  location               = azurerm_resource_group.this.location
  resource_group_name    = azurerm_resource_group.this.name
  os_type                = "Linux"
  sku_name               = var.sku_name
  worker_count           = var.capacity.initial
  zone_balancing_enabled = var.zone_redundant
  tags                   = var.tags

  lifecycle {
    ignore_changes = [worker_count]
    precondition {
      condition     = !var.zone_redundant || var.capacity.minimum >= 3
      error_message = "Zone redundancy requires at least three baseline workers."
    }
  }
}

resource "azurerm_user_assigned_identity" "this" {
  name                = "${var.name}-identity"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = var.tags
}

resource "azurerm_role_assignment" "acr_pull" {
  count                = var.acr_resource_id == null ? 0 : 1
  scope                = var.acr_resource_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.this.principal_id
}

resource "azurerm_linux_web_app" "this" {
  name                                           = var.name
  location                                       = azurerm_resource_group.this.location
  resource_group_name                            = azurerm_resource_group.this.name
  service_plan_id                                = azurerm_service_plan.this.id
  https_only                                     = true
  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = false
  public_network_access_enabled                  = true
  key_vault_reference_identity_id                = azurerm_user_assigned_identity.this.id
  app_settings                                   = local.settings
  tags                                           = var.tags

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.this.id]
  }

  site_config {
    always_on                                     = true
    http2_enabled                                 = true
    minimum_tls_version                           = "1.2"
    scm_minimum_tls_version                       = "1.2"
    ftps_state                                    = "Disabled"
    health_check_path                             = var.health_check_path
    health_check_eviction_time_in_min             = 5
    container_registry_use_managed_identity       = var.acr_resource_id != null
    container_registry_managed_identity_client_id = var.acr_resource_id == null ? null : azurerm_user_assigned_identity.this.client_id
    scm_use_main_ip_restriction                   = true
    ip_restriction_default_action                 = length(var.allowed_ipv4_cidrs) == 0 ? "Allow" : "Deny"

    application_stack {
      docker_image_name   = var.container_image
      docker_registry_url = var.registry_url
    }

    dynamic "ip_restriction" {
      for_each = var.allowed_ipv4_cidrs
      content {
        name       = "allow-${ip_restriction.key}"
        ip_address = ip_restriction.value
        priority   = 100 + ip_restriction.key
        action     = "Allow"
      }
    }
  }

  logs {
    application_logs {
      file_system_level = "Information"
    }
    http_logs {
      file_system {
        retention_in_days = 3
        retention_in_mb   = 35
      }
    }
  }

  depends_on = [azurerm_role_assignment.acr_pull]
}

resource "azurerm_linux_web_app_slot" "staging" {
  count                                          = var.staging_enabled ? 1 : 0
  name                                           = "staging"
  app_service_id                                 = azurerm_linux_web_app.this.id
  https_only                                     = true
  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = false
  public_network_access_enabled                  = true
  key_vault_reference_identity_id                = azurerm_user_assigned_identity.this.id
  app_settings                                   = local.settings
  tags                                           = var.tags

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.this.id]
  }

  site_config {
    always_on                                     = true
    http2_enabled                                 = true
    minimum_tls_version                           = "1.2"
    scm_minimum_tls_version                       = "1.2"
    ftps_state                                    = "Disabled"
    health_check_path                             = var.health_check_path
    health_check_eviction_time_in_min             = 5
    container_registry_use_managed_identity       = var.acr_resource_id != null
    container_registry_managed_identity_client_id = var.acr_resource_id == null ? null : azurerm_user_assigned_identity.this.client_id
    scm_use_main_ip_restriction                   = true
    ip_restriction_default_action                 = length(var.allowed_ipv4_cidrs) == 0 ? "Allow" : "Deny"

    application_stack {
      docker_image_name   = coalesce(var.staging_image, var.container_image)
      docker_registry_url = var.registry_url
    }

    dynamic "ip_restriction" {
      for_each = var.allowed_ipv4_cidrs
      content {
        name       = "allow-${ip_restriction.key}"
        ip_address = ip_restriction.value
        priority   = 100 + ip_restriction.key
        action     = "Allow"
      }
    }
  }

  logs {
    application_logs {
      file_system_level = "Information"
    }
    http_logs {
      file_system {
        retention_in_days = 3
        retention_in_mb   = 35
      }
    }
  }
}
