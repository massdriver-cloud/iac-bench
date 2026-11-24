locals {
  env_normalized = lower(var.environment)
  is_prod        = contains(["prod", "production"], local.env_normalized)

  env_short_map = {
    dev         = "dev"
    development = "dev"
    test        = "tst"
    qa          = "qa"
    staging     = "stg"
    uat         = "uat"
    sandbox     = "sbx"
    prod        = "prd"
    production  = "prd"
  }

  app_sanitized = replace(lower(var.application_name), "/[^a-z0-9]/", "")
  env_short     = lookup(local.env_short_map, local.env_normalized, substr(replace(local.env_normalized, "/[^a-z0-9]/", ""), 0, 3))
  name_hash     = substr(sha256("${var.resource_group_name}:${var.application_name}:${var.environment}:${var.location}"), 0, 6)

  # Azure Storage account names must be 3-24 lowercase alphanumeric characters and globally unique.
  # 2 ("st") + up to 13 (app) + up to 3 (env) + 6 (deterministic hash suffix) <= 24 characters.
  generated_storage_account_name = "st${substr(local.app_sanitized, 0, 13)}${local.env_short}${local.name_hash}"
  storage_account_name           = coalesce(var.storage_account_name_override, local.generated_storage_account_name)

  replication_type           = coalesce(var.replication_type_override, local.is_prod ? "GRS" : "LRS")
  versioning_enabled         = local.is_prod
  blob_soft_delete_days      = local.is_prod ? 30 : 7
  container_soft_delete_days = local.is_prod ? 30 : 7

  has_network_allowlist         = length(var.allowed_subnet_ids) > 0 || length(var.allowed_ip_ranges) > 0
  has_private_endpoint          = var.private_endpoint_subnet_id != null
  public_network_access_enabled = !(local.has_private_endpoint && !local.has_network_allowlist)
  network_default_action        = (local.has_network_allowlist || local.has_private_endpoint) ? "Deny" : "Allow"

  containers_with_lifecycle = {
    for name, cfg in var.containers : name => cfg
    if cfg.lifecycle_tier_to_cool_after_days != null ||
    cfg.lifecycle_tier_to_cold_after_days != null ||
    cfg.lifecycle_delete_after_days != null
  }

  has_lifecycle_policy = local.versioning_enabled || length(local.containers_with_lifecycle) > 0

  default_tags = {
    application = lower(var.application_name)
    environment = local.env_normalized
    managed_by  = "opentofu"
  }

  tags = merge(var.tags, local.default_tags)
}
