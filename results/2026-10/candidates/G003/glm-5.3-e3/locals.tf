locals {
  # -------------------------------------------------------------------------
  # Placement
  # -------------------------------------------------------------------------
  create_resource_group = var.resource_group_name == null

  resource_group_name = coalesce(
    var.resource_group_name,
    one(azurerm_resource_group.this[*].name),
  )

  location = var.resource_group_name == null ? var.location : one(data.azurerm_resource_group.existing[*].location)

  tags = merge(
    {
      service     = var.name
      environment = var.environment
      managed_by  = "opentofu"
    },
    var.tags,
  )

  # Deterministic 5-char suffix: *.azurewebsites.net names are globally unique
  # across all of Azure, so two subscriptions running the same service name must
  # not collide. Being deterministic, rebuilding the service keeps its hostname.
  hostname_suffix = substr(sha256("${var.name}|${var.environment}|${data.azurerm_client_config.current.subscription_id}"), 0, 5)

  web_app_name = "${var.name}-${var.environment}-${local.hostname_suffix}"

  # -------------------------------------------------------------------------
  # Capacity
  # -------------------------------------------------------------------------
  tiers = {
    small  = { sku = "S1", zone_capable = false, instance_limit = 10 }  # 1 vCPU / 1.75 GB
    medium = { sku = "P1v3", zone_capable = true, instance_limit = 30 } # 2 vCPU / 8 GB
    large  = { sku = "P2v3", zone_capable = true, instance_limit = 30 } # 4 vCPU / 16 GB
    xlarge = { sku = "P3v3", zone_capable = true, instance_limit = 30 } # 8 vCPU / 32 GB
  }
  tier = local.tiers[var.tier]

  # Zone spreading on by default wherever the SKU supports it. Premium v3 plans
  # are zone-redundant in zone-capable regions by platform default (the old
  # opt-in flag is gone from the API); zone_balancing_enabled keeps instances
  # evenly spread across the zones those tiers occupy.
  zone_spreading = coalesce(var.zone_redundant, local.tier.zone_capable)

  # A zone-redundant plan needs at least 3 instances to actually land in all
  # three zones, so the floor is raised rather than silently under-delivering.
  effective_min_instances = local.zone_spreading ? max(var.min_instances, 3) : var.min_instances

  container_registry_use_managed_identity = var.container_registry_id != null

  # -------------------------------------------------------------------------
  # Container image reference parsing: "[registry/]repository[:tag]"
  # -------------------------------------------------------------------------
  image_parts = split("/", var.container_image)

  # A first path segment only counts as a registry host when it looks like one
  # (contains a dot, or is "localhost", optionally with a port).
  image_first_part_is_registry = length(local.image_parts) > 1 && (
    can(regex("^([a-z0-9-]+[.][a-z0-9.-]+|localhost)(:[0-9]{1,5})?$", local.image_parts[0]))
  )

  image_registry_host = local.image_first_part_is_registry ? (
    contains(["docker.io", "index.docker.io", "registry-1.docker.io"], local.image_parts[0]) ? "index.docker.io" : local.image_parts[0]
  ) : "index.docker.io"

  image_registry_url = "https://${local.image_registry_host}"

  image_repo_and_tag = local.image_first_part_is_registry ? join("/", slice(local.image_parts, 1, length(local.image_parts))) : var.container_image

  image_last_segment = element(split("/", local.image_repo_and_tag), length(split("/", local.image_repo_and_tag)) - 1)

  image_has_tag = can(regex(":", local.image_last_segment))

  image_tag = local.image_has_tag ? element(split(":", local.image_last_segment), 1) : "latest"

  image_repo = local.image_has_tag ? trimsuffix(local.image_repo_and_tag, ":${local.image_tag}") : local.image_repo_and_tag

  # Docker Hub official images live under library/, which App Service expects
  # when the repository is referenced without an organisation.
  image_repository = (local.image_registry_host == "index.docker.io" && !can(regex("/", local.image_repo))) ? "library/${local.image_repo}" : local.image_repo

  # Flat application_stack schema: repository and tag travel together in
  # docker_image_name, the registry host goes to docker_registry_url.
  docker_image_name = "${local.image_repository}:${local.image_tag}"

  # -------------------------------------------------------------------------
  # App settings
  # -------------------------------------------------------------------------
  built_in_app_settings = {
    WEBSITES_ENABLE_APP_SERVICE_STORAGE   = "false"
    WEBSITES_PORT                         = tostring(var.container_port)
    APPLICATIONINSIGHTS_CONNECTION_STRING = azurerm_application_insights.this.connection_string
    APPINSIGHTS_INSTRUMENTATIONKEY        = azurerm_application_insights.this.instrumentation_key
  }

  app_settings = merge(local.built_in_app_settings, var.app_settings)

  # -------------------------------------------------------------------------
  # Alerting
  # -------------------------------------------------------------------------
  alert_email_receivers = {
    for idx, email in var.alert_emails : format("email-%02d", idx + 1) => email
  }

  action_group_id = one(azurerm_monitor_action_group.this[*].id)
}
