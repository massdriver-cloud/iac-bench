locals {
  is_prod = var.environment == "prod"

  # Compliant Azure Storage Account naming:
  # 3-24 chars, lowercase alphanumeric only, globally unique.
  # Format: "st" (2) + sanitized app name (2..13) + env code (3) + random suffix (6) = 13..24 chars.
  env_short_map = {
    dev     = "dev"
    test    = "tst"
    staging = "stg"
    prod    = "prd"
  }

  app_name_clean       = lower(replace(var.application_name, "/[^a-zA-Z0-9]/", ""))
  app_name_truncated   = substr(local.app_name_clean, 0, min(length(local.app_name_clean), 13))
  storage_account_name = "st${local.app_name_truncated}${local.env_short_map[var.environment]}${random_string.suffix.result}"

  # Environment-aware redundancy:
  # - prod:     ZRS by default (3-zone synchronous HA), GZRS when geo-redundancy is enabled
  # - non-prod: LRS by default (cost-efficient), GRS when geo-redundancy is enabled
  replication_type = local.is_prod ? (
    var.enable_geo_redundancy ? "GZRS" : "ZRS"
    ) : (
    var.enable_geo_redundancy ? "GRS" : "LRS"
  )

  # Environment-aware data protection:
  blob_soft_delete_days         = local.is_prod ? 30 : 7
  container_soft_delete_days    = local.is_prod ? 30 : 7
  point_in_time_restore_days    = 14 # Used in prod only; must be < blob_soft_delete_days (30)
  noncurrent_version_delete_day = local.is_prod ? 90 : 14

  # Delete protection lock defaults to true in prod, false in non-prod.
  create_delete_lock = coalesce(var.enable_delete_lock, local.is_prod)

  # Networking: disable public endpoint completely when a Private Endpoint is provisioned.
  use_private_endpoint          = var.private_endpoint_subnet_id != null
  public_network_access_enabled = !local.use_private_endpoint

  # Deduplicated Entra ID principal sets for RBAC assignments.
  contributor_principal_ids = setunion(
    toset([var.app_principal_id]),
    var.additional_contributor_principal_ids
  )

  # Containers that declare an automatic expiration policy (e.g. generated reports/exports).
  expiring_containers = {
    for name, cfg in var.containers :
    name => cfg.retention_days
    if cfg.retention_days != null
  }

  # Standard governance tags merged with caller-supplied tags.
  # Module-enforced keys override caller keys to guarantee consistent tagging across teams.
  standard_tags = merge(
    var.tags,
    {
      application = var.application_name
      environment = var.environment
      managed_by  = "opentofu"
    }
  )
}
