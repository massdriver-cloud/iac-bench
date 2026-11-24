locals {
  is_prod = var.environment == "prod"

  # ---------------------------------------------------------------------------
  # Naming: Azure storage accounts require 3-24 lowercase alphanumeric chars,
  # globally unique across Azure. Format: st + <app:2..13> + <env:3> + <hash:6>
  # The 6-char suffix is derived deterministically from subscription + RG + app + env
  # so names are globally unique across organizations without external providers.
  # ---------------------------------------------------------------------------
  env_short_map = {
    dev     = "dev"
    test    = "tst"
    staging = "stg"
    prod    = "prd"
  }

  sanitized_app = lower(replace(var.application_name, "/[^a-zA-Z0-9]/", ""))
  app_segment   = substr(local.sanitized_app, 0, min(13, length(local.sanitized_app)))
  env_short     = local.env_short_map[var.environment]
  name_seed     = "${data.azurerm_client_config.current.subscription_id}/${var.resource_group_name}/${var.application_name}/${var.environment}"
  name_suffix   = coalesce(var.name_suffix, substr(sha256(local.name_seed), 0, 6))

  storage_account_name = "st${local.app_segment}${local.env_short}${local.name_suffix}"

  # ---------------------------------------------------------------------------
  # Environment-Aware Resilience & Data Protection Defaults
  # ---------------------------------------------------------------------------
  default_replication_map = {
    dev     = "LRS"
    test    = "LRS"
    staging = "ZRS"
    prod    = "GRS"
  }

  replication_type           = coalesce(var.replication_type, local.default_replication_map[var.environment])
  blob_soft_delete_days      = coalesce(var.blob_soft_delete_days, local.is_prod ? 30 : 7)
  container_soft_delete_days = coalesce(var.container_soft_delete_days, local.is_prod ? 30 : 7)
  versioning_enabled         = var.versioning_enabled

  # Point-in-time restore: enabled (7 days) in prod by default, disabled in non-prod.
  # Setting point_in_time_restore_days = 0 explicitly disables it in any environment.
  raw_pitr_days              = var.point_in_time_restore_days != null ? var.point_in_time_restore_days : (local.is_prod ? 7 : 0)
  point_in_time_restore_days = local.raw_pitr_days > 0 ? local.raw_pitr_days : null
  change_feed_enabled        = local.point_in_time_restore_days != null || local.is_prod

  noncurrent_version_retention_days = coalesce(var.noncurrent_version_retention_days, local.is_prod ? 90 : 30)
  enable_delete_lock                = var.enable_delete_lock != null ? var.enable_delete_lock : local.is_prod

  # Automatically disable public network access when a Private Endpoint is configured
  # unless the caller explicitly overrides public_network_access_enabled.
  public_network_access_enabled = var.public_network_access_enabled != null ? var.public_network_access_enabled : (var.private_endpoint == null)

  # ---------------------------------------------------------------------------
  # Lifecycle Management Rules
  # ---------------------------------------------------------------------------
  container_lifecycle_rules = {
    for name, cfg in var.containers : name => cfg
    if cfg.tier_to_cool_after_days != null || cfg.tier_to_archive_after_days != null || cfg.delete_after_days != null
  }

  has_lifecycle_policy = (
    local.versioning_enabled ||
    length(local.container_lifecycle_rules) > 0 ||
    length(var.additional_lifecycle_rules) > 0
  )

  # ---------------------------------------------------------------------------
  # Standardized Tags
  # ---------------------------------------------------------------------------
  optional_governance_tags = merge(
    var.owner != null ? { owner = var.owner } : {},
    var.cost_center != null ? { cost_center = var.cost_center } : {},
  )

  standard_tags = {
    application = var.application_name
    environment = var.environment
    managed_by  = "opentofu"
  }

  tags = merge(var.tags, local.optional_governance_tags, local.standard_tags)
}
