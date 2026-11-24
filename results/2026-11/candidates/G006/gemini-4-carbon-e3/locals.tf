locals {
  normalized_environment = lower(var.environment)
  is_production          = contains(["prod", "production"], local.normalized_environment)

  # Follow the standard '<app_name>-<environment>' convention unless overridden.
  resource_group_name = coalesce(var.resource_group_name, "${var.app_name}-${local.normalized_environment}")
  location            = var.location != null ? var.location : data.azurerm_resource_group.this[0].location
  rg_tags             = var.location == null && data.azurerm_resource_group.this[0].tags != null ? data.azurerm_resource_group.this[0].tags : {}

  # Deterministic, globally unique 3-24 char lowercase alphanumeric storage account name:
  # 'st' (2) + app_slug (<= 14) + env_slug (<= 7) + 7-char subscription/RG/app SHA-256 prefix (<= 24 total).
  clean_app   = replace(lower(var.app_name), "/[^a-z0-9]/", "")
  clean_env   = replace(local.normalized_environment, "/[^a-z0-9]/", "")
  env_slug    = substr(local.clean_env, 0, min(length(local.clean_env), 7))
  app_max_len = 15 - length(local.env_slug)
  app_slug    = substr(local.clean_app, 0, min(length(local.clean_app), local.app_max_len))
  unique_hash = substr(
    sha256("${data.azurerm_client_config.current.subscription_id}/${local.resource_group_name}/${var.app_name}/${local.normalized_environment}"),
    0,
    7
  )

  storage_account_name = coalesce(
    var.storage_account_name_override,
    "st${local.app_slug}${local.env_slug}${local.unique_hash}"
  )

  # Environment-aware durability, recovery, and lifecycle defaults.
  replication_type                  = coalesce(var.replication_type, local.is_production ? "GZRS" : "LRS")
  soft_delete_days                  = coalesce(var.soft_delete_retention_days, local.is_production ? 30 : 7)
  enable_change_feed                = var.enable_change_feed != null ? var.enable_change_feed : local.is_production
  noncurrent_version_retention_days = coalesce(var.noncurrent_version_retention_days, local.is_production ? 90 : 30)

  # Network security defaults:
  # - Automatically lock firewall default_action to 'Deny' when VNet subnets or IP rules are configured.
  # - Automatically disable public network access when a Private Endpoint is provisioned.
  has_network_restrictions      = length(var.allowed_subnet_ids) > 0 || length(var.allowed_ip_ranges) > 0
  network_default_action        = coalesce(var.network_default_action, local.has_network_restrictions ? "Deny" : "Allow")
  public_network_access_enabled = var.public_network_access_enabled != null ? var.public_network_access_enabled : (var.private_endpoint_subnet_id == null)

  # Secondary Entra ID principal sets (kept independent of var.app_principal_id so
  # var.app_principal_id can safely accept unknown/apply-time principal IDs).
  additional_contributor_ids = toset([for id in var.additional_contributor_principal_ids : lower(id)])
  additional_delegator_ids   = var.enable_user_delegation_sas ? local.additional_contributor_ids : toset([])
  reader_ids = setsubtract(
    toset([for id in var.reader_principal_ids : lower(id)]),
    local.additional_contributor_ids
  )

  # Per-container custom lifecycle policies.
  containers_with_custom_lifecycle = {
    for name, cfg in var.containers : name => cfg
    if cfg.delete_after_days != null || cfg.cool_after_days != null || cfg.cold_after_days != null
  }
  create_lifecycle_policy = var.enable_lifecycle_policy || length(local.containers_with_custom_lifecycle) > 0

  default_tags = {
    application = var.app_name
    environment = local.normalized_environment
    managed_by  = "opentofu"
  }

  tags = merge(local.rg_tags, local.default_tags, var.tags)
}
