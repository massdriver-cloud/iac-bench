locals {
  base_name = "${var.name}-${var.environment}"

  # Web app names are global DNS labels (<name>.azurewebsites.net); a short
  # random suffix, stable for the life of the deployment, avoids collisions.
  app_name  = "app-${local.base_name}-${random_string.suffix.result}"
  slot_name = "staging"

  resource_group_name = var.resource_group_name != null ? var.resource_group_name : azurerm_resource_group.this[0].name

  tags = merge(
    {
      service     = var.name
      environment = var.environment
      managed-by  = "opentofu"
    },
    var.tags,
  )

  # --- Container images ------------------------------------------------------
  # "<registry host>/<repository>:<tag>" -> registry URL + "<repository>:<tag>"
  image_refs = {
    production = var.image
    staging    = coalesce(var.staging_image, var.image)
  }

  images = {
    for slot, ref in local.image_refs :
    slot => {
      registry_url = "https://${regex("^([^/]+)/(.+)$", ref)[0]}"
      name         = regex("^([^/]+)/(.+)$", ref)[1]
      # Azure Container Registry is always pulled with the managed identity;
      # there is deliberately no support for registry passwords.
      use_managed_identity = can(regex("\\.azurecr\\.(io|cn|us)$", regex("^([^/]+)/(.+)$", ref)[0]))
    }
  }

  # --- App settings ----------------------------------------------------------
  key_vault_references = {
    for name, uri in var.key_vault_secrets : name => "@Microsoft.KeyVault(SecretUri=${uri})"
  }

  managed_app_settings = {
    WEBSITES_PORT                         = tostring(var.container_port)
    WEBSITES_ENABLE_APP_SERVICE_STORAGE   = "false"
    WEBSITE_SWAP_WARMUP_PING_PATH         = var.health_check_path
    WEBSITE_SWAP_WARMUP_PING_STATUSES     = "200,202,204"
    APPLICATIONINSIGHTS_CONNECTION_STRING = azurerm_application_insights.this.connection_string
    # Lets Azure SDKs (DefaultAzureCredential) pick the service identity.
    AZURE_CLIENT_ID = azurerm_user_assigned_identity.this.client_id
  }

  # Module-managed settings always win; staging overrides sit on top of the
  # production values.
  app_settings = merge(
    var.app_settings,
    local.key_vault_references,
    local.managed_app_settings,
  )
  staging_app_settings = merge(
    var.app_settings,
    local.key_vault_references,
    var.staging_app_settings,
    local.managed_app_settings,
  )

  sticky_app_setting_names = var.staging_slot_enabled ? sort(keys(var.staging_app_settings)) : []

  # --- Inbound access rules --------------------------------------------------
  ip_restrictions = concat(
    [
      for i, cidr in var.allowed_ip_ranges : {
        name          = "allow-range-${i + 1}"
        priority      = 100 + i
        ip_address    = cidr
        service_tag   = null
        front_door_id = null
      }
    ],
    [
      for i, tag in var.allowed_service_tags : {
        name          = "allow-tag-${i + 1}"
        priority      = 300 + i
        ip_address    = null
        service_tag   = tag
        front_door_id = null
      }
    ],
    [
      for id in var.front_door_id[*] : {
        name          = "allow-front-door"
        priority      = 500
        ip_address    = null
        service_tag   = "AzureFrontDoor.Backend"
        front_door_id = id
      }
    ],
  )

  # Open to the internet only when no allow-list is given at all.
  ip_restriction_default_action = length(local.ip_restrictions) > 0 ? "Deny" : "Allow"

  # --- Observability ---------------------------------------------------------
  log_analytics_workspace_id = var.log_analytics_workspace_id != null ? var.log_analytics_workspace_id : azurerm_log_analytics_workspace.this[0].id

  log_categories = [
    "AppServiceHTTPLogs",
    "AppServiceConsoleLogs",
    "AppServiceAppLogs",
    "AppServicePlatformLogs",
    "AppServiceAuditLogs",
    "AppServiceIPSecAuditLogs",
  ]

  alert_action_group_ids = concat(var.alert_action_group_ids, azurerm_monitor_action_group.email[*].id)

  metric_alert_definitions = {
    "http-5xx" = {
      description = "${var.name} (${var.environment}) returned more than ${var.alert_thresholds.http_5xx_count} HTTP 5xx responses in 5 minutes."
      target      = "app"
      metric      = "Http5xx"
      aggregation = "Total"
      operator    = "GreaterThan"
      threshold   = var.alert_thresholds.http_5xx_count
      window      = "PT5M"
      frequency   = "PT1M"
      severity    = 1
    }
    "response-time" = {
      description = "${var.name} (${var.environment}) average response time exceeded ${var.alert_thresholds.response_time_seconds}s over 5 minutes."
      target      = "app"
      metric      = "HttpResponseTime"
      aggregation = "Average"
      operator    = "GreaterThan"
      threshold   = var.alert_thresholds.response_time_seconds
      window      = "PT5M"
      frequency   = "PT1M"
      severity    = 2
    }
    "health-check" = {
      description = "Fewer than ${var.alert_thresholds.health_check_percent}% of ${var.name} (${var.environment}) instances passed ${var.health_check_path} over 5 minutes."
      target      = "app"
      metric      = "HealthCheckStatus"
      aggregation = "Average"
      operator    = "LessThan"
      threshold   = var.alert_thresholds.health_check_percent
      window      = "PT5M"
      frequency   = "PT1M"
      severity    = 1
    }
    "plan-cpu" = {
      description = "Plan CPU for ${var.name} (${var.environment}) stayed above ${var.alert_thresholds.cpu_percent}% for 15 minutes: autoscale is not keeping up or is at max_instances."
      target      = "plan"
      metric      = "CpuPercentage"
      aggregation = "Average"
      operator    = "GreaterThan"
      threshold   = var.alert_thresholds.cpu_percent
      window      = "PT15M"
      frequency   = "PT5M"
      severity    = 2
    }
    "plan-memory" = {
      description = "Plan memory for ${var.name} (${var.environment}) stayed above ${var.alert_thresholds.memory_percent}% for 15 minutes."
      target      = "plan"
      metric      = "MemoryPercentage"
      aggregation = "Average"
      operator    = "GreaterThan"
      threshold   = var.alert_thresholds.memory_percent
      window      = "PT15M"
      frequency   = "PT5M"
      severity    = 2
    }
  }

  metric_alerts = { for name, alert in local.metric_alert_definitions : name => alert if var.alerts_enabled }
}
