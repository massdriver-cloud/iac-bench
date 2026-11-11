data "azurerm_client_config" "current" {}

locals {
  workload = "${var.name}-${var.environment}"

  # Resource group: create one unless the caller points at an existing group.
  create_resource_group      = var.resource_group_name == null
  resource_group_name_static = coalesce(var.resource_group_name, "rg-${local.workload}")
  resource_group_name        = local.create_resource_group ? azurerm_resource_group.this[0].name : var.resource_group_name

  # Web app host names are a global namespace. A short hash that is stable for
  # a given subscription / resource group / workload keeps the default name
  # deterministic while avoiding collisions with other tenants.
  name_hash = substr(sha256("${data.azurerm_client_config.current.subscription_id}/${local.resource_group_name_static}/${local.workload}"), 0, 6)
  app_name  = coalesce(var.app_name, "app-${local.workload}-${local.name_hash}")

  slot_name = "staging"

  tags = merge(
    {
      workload    = var.name
      environment = var.environment
      managed-by  = "opentofu"
    },
    var.tags,
  )

  # --- Container ------------------------------------------------------------
  registry_is_acr     = endswith(lower(var.image.registry), ".azurecr.io")
  docker_registry_url = "https://${var.image.registry}"
  docker_image_name   = "${var.image.repository}:${var.image.tag}"

  # --- App settings -----------------------------------------------------------
  platform_app_settings = merge(
    {
      WEBSITES_PORT                       = tostring(var.container_port)
      WEBSITES_ENABLE_APP_SERVICE_STORAGE = "false"
      # A slot swap only completes once every instance answers the health
      # endpoint successfully with the production configuration applied.
      WEBSITE_SWAP_WARMUP_PING_PATH     = var.health_check_path
      WEBSITE_SWAP_WARMUP_PING_STATUSES = "200,204"
    },
    var.application_insights_enabled ? {
      APPLICATIONINSIGHTS_CONNECTION_STRING = azurerm_application_insights.this[0].connection_string
    } : {},
  )

  app_settings = merge(
    var.app_settings,
    { for k, uri in var.key_vault_secrets : k => "@Microsoft.KeyVault(SecretUri=${uri})" },
    local.platform_app_settings,
  )

  # --- Ingress ----------------------------------------------------------------
  public_network_access_enabled = var.ingress.mode != "private"
  # Default-deny everywhere except for an explicitly public app.
  ip_restriction_default_action = var.ingress.mode == "public" ? "Allow" : "Deny"

  ingress_rules = concat(
    [for i, cidr in var.ingress.allowed_cidrs : {
      name        = "allow-cidr-${i}"
      ip_address  = cidr
      service_tag = null
      subnet_id   = null
      fd_ids      = []
    }],
    [for i, tag in var.ingress.allowed_service_tags : {
      name        = "allow-tag-${i}"
      ip_address  = null
      service_tag = tag
      subnet_id   = null
      fd_ids      = []
    }],
    [for i, subnet_id in var.ingress.allowed_subnet_ids : {
      name        = "allow-subnet-${i}"
      ip_address  = null
      service_tag = null
      subnet_id   = subnet_id
      fd_ids      = []
    }],
    length(var.ingress.front_door_ids) > 0 ? [{
      name        = "allow-front-door"
      ip_address  = null
      service_tag = "AzureFrontDoor.Backend"
      subnet_id   = null
      fd_ids      = var.ingress.front_door_ids
    }] : [],
  )

  create_private_endpoints = var.ingress.private_endpoint_subnet_id != null

  # --- Observability ----------------------------------------------------------
  create_workspace           = var.log_analytics_workspace_id == null
  log_analytics_workspace_id = local.create_workspace ? azurerm_log_analytics_workspace.this[0].id : var.log_analytics_workspace_id

  app_log_categories = [
    "AppServiceHTTPLogs",
    "AppServiceConsoleLogs",
    "AppServiceAppLogs",
    "AppServicePlatformLogs",
    "AppServiceAuditLogs",
    "AppServiceIPSecAuditLogs",
  ]
}
