locals {
  is_production = contains(["prod", "production", "prd"], lower(var.environment))

  # Azure regions without Availability Zones where ZRS is unavailable (fall back to GRS in production)
  non_az_regions = toset([
    "australiacentral",
    "australiacentral2",
    "australiasoutheast",
    "brazilsoutheast",
    "canadaeast",
    "francesouth",
    "germanynorth",
    "japanwest",
    "koreasouth",
    "northcentralus",
    "norwaywest",
    "southindia",
    "switzerlandwest",
    "uaecentral",
    "ukwest",
    "westcentralus",
    "westindia",
    "westus",
  ])

  default_prod_replication = contains(local.non_az_regions, lower(var.location)) ? "GRS" : "ZRS"

  clean_app   = replace(lower(var.app_name), "/[^a-z0-9]/", "")
  clean_env   = replace(lower(var.environment), "/[^a-z0-9]/", "")
  name_prefix = substr("st${local.clean_app}${local.clean_env}", 0, 18)

  storage_account_name = coalesce(
    var.storage_account_name_override,
    "${local.name_prefix}${random_string.suffix[0].result}"
  )

  replication_type        = coalesce(var.replication_type, local.is_production ? local.default_prod_replication : "LRS")
  soft_delete_days        = var.soft_delete_retention_days != null ? var.soft_delete_retention_days : (local.is_production ? 30 : 7)
  noncurrent_version_days = var.noncurrent_version_retention_days != null ? var.noncurrent_version_retention_days : (local.is_production ? 90 : 14)

  normalized_ip_rules       = sort([for ip in var.allowed_ip_ranges : trimsuffix(trimspace(ip), "/32")])
  has_public_firewall_rules = length(var.allowed_subnet_ids) > 0 || length(var.allowed_ip_ranges) > 0

  public_network_access_enabled = (
    var.public_network_access_enabled != null
    ? var.public_network_access_enabled
    : (var.private_endpoint_subnet_id != null && !local.has_public_firewall_rules ? false : true)
  )

  network_default_action = coalesce(
    var.network_default_action,
    local.has_public_firewall_rules || !local.public_network_access_enabled ? "Deny" : "Allow"
  )

  container_lifecycle_rules = {
    for name, cfg in var.containers : name => cfg
    if cfg.cool_after_days != null || cfg.cold_after_days != null || cfg.delete_after_days != null
  }

  enable_version_cleanup_rule = var.versioning_enabled && local.noncurrent_version_days > 0
  enable_management_policy    = local.enable_version_cleanup_rule || length(local.container_lifecycle_rules) > 0

  # Deduplicate additional principals if a reader is also listed in additional contributors
  additional_reader_ids = setsubtract(var.additional_reader_principal_ids, var.additional_contributor_principal_ids)

  default_tags = {
    application = var.app_name
    environment = var.environment
    managed_by  = "opentofu"
  }

  tags = merge(local.default_tags, var.tags)
}
