data "azurerm_client_config" "current" {}

locals {
  is_prod = var.environment == "prod"

  # Deterministic, globally unique, Azure-compliant storage account name (3-24 lowercase alphanumeric).
  # Format: "st" (2) + app_slug (<=12) + env_slug (<=4) + sha256_hash (6) => 10..24 chars.
  app_slug  = replace(lower(var.app_name), "/[^a-z0-9]/", "")
  env_slug  = replace(lower(var.environment), "/[^a-z0-9]/", "")
  name_hash = substr(sha256("${data.azurerm_client_config.current.subscription_id}/${var.resource_group_name}/${var.app_name}/${var.environment}"), 0, 6)

  generated_storage_account_name = format(
    "st%s%s%s",
    substr(local.app_slug, 0, min(length(local.app_slug), 12)),
    substr(local.env_slug, 0, min(length(local.env_slug), 4)),
    local.name_hash,
  )

  storage_account_name = coalesce(var.storage_account_name_override, local.generated_storage_account_name)

  # Environment-driven reliability & data protection defaults
  replication_type                = coalesce(var.replication_type, local.is_prod ? "GRS" : "LRS")
  blob_soft_delete_days           = coalesce(var.blob_soft_delete_days, local.is_prod ? 30 : 7)
  container_soft_delete_days      = coalesce(var.container_soft_delete_days, local.is_prod ? 30 : 7)
  pitr_days                       = coalesce(var.point_in_time_restore_days, local.is_prod && local.blob_soft_delete_days > 1 ? min(14, local.blob_soft_delete_days - 1) : 0)
  previous_version_retention_days = coalesce(var.previous_version_retention_days, local.is_prod ? 90 : 30)
  enable_delete_lock              = coalesce(var.enable_delete_lock, local.is_prod)

  # Disable public endpoint automatically when Private Endpoint is configured (unless explicitly overridden)
  public_network_access_enabled = coalesce(var.allow_public_network_access, var.private_endpoint == null)

  # RBAC sets
  contributor_principal_ids = setunion([var.app_principal_id], var.additional_contributor_principal_ids)

  # Containers that declare at least one lifecycle rule
  containers_with_lifecycle = {
    for name, cfg in var.containers : name => cfg
    if cfg.cool_after_days != null || cfg.archive_after_days != null || cfg.expire_after_days != null
  }

  # Standard governance tags merged with caller tags
  tags = merge(
    {
      application = var.app_name
      environment = var.environment
      managed_by  = "opentofu"
    },
    var.tags,
  )
}
