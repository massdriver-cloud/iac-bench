# Standard App Service module for the SRE team.
#
# One service = one resource group, one Linux App Service plan, one Linux web
# app running a container, plus a staging slot, autoscale, managed-identity
# registry access and a full observability pipeline. The module owns the App
# Service internals (TLS, FTPS off, Always On, HTTP/2, auto-heal, log
# plumbing); callers think in capacity, availability, health, rollouts and
# observability.

resource "azurerm_resource_group" "this" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

# --- Capacity ---------------------------------------------------------------

resource "azurerm_service_plan" "this" {
  name                   = "${var.name}-plan"
  resource_group_name    = azurerm_resource_group.this.name
  location               = azurerm_resource_group.this.location
  os_type                = "Linux"
  sku_name               = var.plan_sku
  worker_count           = var.plan_instances
  zone_balancing_enabled = var.zone_redundant
  tags                   = var.tags
}

resource "azurerm_monitor_autoscale_setting" "this" {
  count = var.autoscale_enabled ? 1 : 0

  name                = "${var.name}-autoscale"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  target_resource_id  = azurerm_service_plan.this.id
  tags                = var.tags

  profile {
    name = "cpu"

    capacity {
      minimum = tostring(var.autoscale_min_instances)
      maximum = tostring(var.autoscale_max_instances)
      default = tostring(var.plan_instances)
    }

    # Scale out: sustained CPU pressure.
    rule {
      metric_trigger {
        metric_name        = "CpuPercentage"
        metric_resource_id = azurerm_service_plan.this.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT10M"
        time_aggregation   = "Average"
        operator           = "GreaterThan"
        threshold          = 70
      }

      scale_action {
        direction = "Increase"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT5M"
      }
    }

    # Scale in: comfortably idle, with a longer cooldown to avoid flapping.
    rule {
      metric_trigger {
        metric_name        = "CpuPercentage"
        metric_resource_id = azurerm_service_plan.this.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT10M"
        time_aggregation   = "Average"
        operator           = "LessThan"
        threshold          = 25
      }

      scale_action {
        direction = "Decrease"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT10M"
      }
    }
  }
}

# --- The app ----------------------------------------------------------------

resource "azurerm_linux_web_app" "this" {
  name                = var.name
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  service_plan_id     = azurerm_service_plan.this.id
  tags                = var.tags

  # Stateless HTTP APIs behind a load balancer: no ARR affinity cookie,
  # HTTPS only.
  https_only              = true
  client_affinity_enabled = false

  identity {
    type = "SystemAssigned"
  }

  site_config {
    # Decisions the module owns so SREs don't hand-tune per app:
    always_on               = true # keep workers warm; required for health checks + slots
    http2_enabled           = true
    minimum_tls_version     = "1.2"
    scm_minimum_tls_version = "1.2"
    ftps_state              = "Disabled"

    # Health: poll the readiness endpoint, evict instances that stay sick.
    health_check_path                 = var.health_check_path
    health_check_eviction_time_in_min = var.health_check_eviction_time_in_min

    # Pull from ACR with the managed identity when acr_id is provided.
    container_registry_use_managed_identity = var.acr_id != null

    application_stack {
      docker_image_name   = var.container_image
      docker_registry_url = var.container_registry_url
    }

    # Self-healing (enabled by the presence of this block): recycle a worker
    # that serves sustained 5xx or goes slow, so a wedged process recovers
    # without paging anyone.
    auto_heal_setting {
      trigger {
        status_code {
          count             = 10
          interval          = "00:05:00"
          status_code_range = "500-599"
        }

        slow_request {
          count      = 10
          interval   = "00:05:00"
          time_taken = "00:00:10"
        }
      }

      action {
        action_type                    = "Recycle"
        minimum_process_execution_time = "00:01:00"
      }
    }
  }

  app_settings = local.app_settings

  # Keep a short tail of logs on the filesystem; the durable copy streams to
  # Log Analytics via the diagnostic setting.
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

# --- Rollouts: staging slot -------------------------------------------------

resource "azurerm_linux_web_app_slot" "staging" {
  count = var.deployment_slot_enabled ? 1 : 0

  name           = "staging"
  app_service_id = azurerm_linux_web_app.this.id
  tags           = var.tags

  https_only = true

  identity {
    type = "SystemAssigned"
  }

  site_config {
    always_on           = true # warm, so swaps are instant
    http2_enabled       = true
    minimum_tls_version = "1.2"
    ftps_state          = "Disabled"

    health_check_path = var.health_check_path

    container_registry_use_managed_identity = var.acr_id != null

    application_stack {
      docker_image_name   = var.container_image
      docker_registry_url = var.container_registry_url
    }
  }

  app_settings = local.app_settings
}

# --- Registry access via managed identity -----------------------------------

resource "azurerm_role_assignment" "acr_pull" {
  count = var.acr_id != null ? 1 : 0

  scope                = var.acr_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_linux_web_app.this.identity[0].principal_id
}

resource "azurerm_role_assignment" "acr_pull_staging" {
  count = var.acr_id != null && var.deployment_slot_enabled ? 1 : 0

  scope                = var.acr_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_linux_web_app_slot.staging[0].identity[0].principal_id
}
