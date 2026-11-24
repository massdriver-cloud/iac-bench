locals {
  # Deterministic hash to guarantee name uniqueness while keeping names predictable
  name_hash = substr(sha256("${var.resource_group_name}-${var.location}-${var.service_name}"), 0, 6)

  # Resource names
  app_name  = coalesce(var.custom_app_name, "app-${var.service_name}-${var.environment}-${local.name_hash}")
  plan_name = coalesce(var.custom_plan_name, "asp-${var.service_name}-${var.environment}-${local.name_hash}")
  law_name  = "law-${var.service_name}-${var.environment}-${local.name_hash}"
  ai_name   = "appi-${var.service_name}-${var.environment}-${local.name_hash}"

  # Resource Group & Location
  resource_group_name = var.create_resource_group ? azurerm_resource_group.this[0].name : var.resource_group_name
  location            = var.create_resource_group ? azurerm_resource_group.this[0].location : var.location

  # Standard SRE metadata tags
  default_tags = {
    "Service"     = var.service_name
    "Environment" = var.environment
    "ManagedBy"   = "OpenTofu"
    "Role"        = "Web-API"
    "Team"        = "SRE"
  }
  tags = merge(local.default_tags, var.tags)

  # Capacity & Availability Calculations:
  # When zone balancing is enabled, Azure requires at least 3 instances to satisfy zone distribution.
  effective_min_capacity     = var.zone_redundancy_enabled ? max(var.min_capacity, 3) : var.min_capacity
  effective_default_capacity = var.zone_redundancy_enabled ? max(var.default_capacity, 3) : var.default_capacity
  effective_max_capacity     = max(var.max_capacity, local.effective_min_capacity)

  # Service Plan ID resolution
  service_plan_id = var.service_plan_id != null ? var.service_plan_id : azurerm_service_plan.this[0].id

  # Observability IDs
  log_analytics_workspace_id = var.log_analytics_workspace_id != null ? var.log_analytics_workspace_id : azurerm_log_analytics_workspace.this[0].id
  application_insights_connection_string = var.application_insights_connection_string != null ? var.application_insights_connection_string : (
    length(azurerm_application_insights.this) > 0 ? azurerm_application_insights.this[0].connection_string : ""
  )

  # Standard App Settings injected into container environment
  # SRE best practice: stateless container apps, explicit port routing, APM extension
  base_app_settings = {
    "WEBSITES_PORT"                              = tostring(var.container_port)
    "PORT"                                       = tostring(var.container_port)
    "WEBSITES_ENABLE_APP_SERVICE_STORAGE"        = "false"
    "DOCKER_ENABLE_CI"                           = "false"
    "APPLICATIONINSIGHTS_CONNECTION_STRING"      = local.application_insights_connection_string
    "ApplicationInsightsAgent_EXTENSION_VERSION" = "~3"
    "XDT_MicrosoftApplicationInsights_Mode"      = "recommended"
  }

  production_app_settings = merge(
    local.base_app_settings,
    {
      "SLOT_NAME"   = "production"
      "APP_ENV"     = var.environment
      "ENVIRONMENT" = var.environment
    },
    var.custom_app_settings
  )

  staging_app_settings = merge(
    local.base_app_settings,
    {
      "SLOT_NAME"   = "staging"
      "APP_ENV"     = "${var.environment}-staging"
      "ENVIRONMENT" = "${var.environment}-staging"
    },
    var.custom_app_settings,
    var.staging_custom_app_settings
  )
}
