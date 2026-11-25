locals {
  is_prod = contains(["prod", "production", "prd"], var.environment)

  # ---------------------------------------------------------------------------
  # Storage Account Naming (Azure rule: 3-24 chars, lowercase a-z and 0-9 only)
  # Format: "st" (2) + app_part (<=12..15) + env_part (<=4) + random (6) <= 24
  # ---------------------------------------------------------------------------
  env_short_map = {
    production  = "prod"
    staging     = "stg"
    development = "dev"
  }

  clean_app     = replace(lower(var.app_name), "/[^a-z0-9]/", "")
  clean_env_raw = replace(lower(var.environment), "/[^a-z0-9]/", "")
  env_part      = lookup(local.env_short_map, var.environment, substr(local.clean_env_raw, 0, min(length(local.clean_env_raw), 4)))
  max_app_chars = 16 - length(local.env_part)
  app_part      = substr(local.clean_app, 0, min(length(local.clean_app), local.max_app_chars))

  generated_storage_account_name = "st${local.app_part}${local.env_part}${random_string.storage_suffix.result}"
  storage_account_name           = coalesce(var.storage_account_name_override, local.generated_storage_account_name)

  # ---------------------------------------------------------------------------
  # Environment-Aware Resilience & Data Protection Defaults
  # ---------------------------------------------------------------------------
  replication_type        = coalesce(var.replication_type, local.is_prod ? "GZRS" : "LRS")
  soft_delete_days        = coalesce(var.soft_delete_retention_days, local.is_prod ? 30 : 7)
  default_pitr_days       = local.is_prod ? min(14, max(0, local.soft_delete_days - 1)) : 0
  pitr_days               = var.point_in_time_restore_days != null ? var.point_in_time_restore_days : local.default_pitr_days
  noncurrent_version_days = coalesce(var.noncurrent_version_retention_days, local.is_prod ? 90 : 30)
  enable_delete_lock      = var.enable_delete_lock != null ? var.enable_delete_lock : local.is_prod

  # ---------------------------------------------------------------------------
  # Network Posture
  # Azure Storage ip_rules rejects '/32' suffixes on single IPs; strip safely.
  # ---------------------------------------------------------------------------
  normalized_ip_rules       = sort([for ip in var.allowed_ip_ranges : trimsuffix(trimspace(ip), "/32")])
  has_public_firewall_rules = length(var.allowed_subnet_ids) > 0 || length(local.normalized_ip_rules) > 0

  public_network_access_enabled = (
    var.public_network_access_enabled != null
    ? var.public_network_access_enabled
    : (var.private_endpoint_subnet_id != null && !local.has_public_firewall_rules ? false : true)
  )

  network_default_action = (
    local.has_public_firewall_rules || var.private_endpoint_subnet_id != null
    ? "Deny"
    : "Allow"
  )

  # ---------------------------------------------------------------------------
  # Container Lifecycle Overrides
  # ---------------------------------------------------------------------------
  containers_with_custom_lifecycle = {
    for cname, cfg in var.containers : cname => cfg
    if cfg.delete_after_days != null || cfg.cool_after_days != null || cfg.cold_after_days != null
  }

  # ---------------------------------------------------------------------------
  # RBAC Assignment Normalization
  # ---------------------------------------------------------------------------
  account_reader_principal_ids = setsubtract(var.reader_principal_ids, var.additional_writer_principal_ids)

  container_writer_assignments = merge([
    for cname, cfg in var.containers : {
      for pid in cfg.writer_principal_ids : "${cname}:${pid}" => {
        container    = cname
        principal_id = pid
      }
      if !contains(var.additional_writer_principal_ids, pid)
    }
  ]...)

  container_reader_assignments = merge([
    for cname, cfg in var.containers : {
      for pid in cfg.reader_principal_ids : "${cname}:${pid}" => {
        container    = cname
        principal_id = pid
      }
      if !contains(var.additional_writer_principal_ids, pid) &&
      !contains(var.reader_principal_ids, pid) &&
      !contains(cfg.writer_principal_ids, pid)
    }
  ]...)

  # ---------------------------------------------------------------------------
  # Standard Resource Tags
  # ---------------------------------------------------------------------------
  tags = merge(
    {
      application = var.app_name
      environment = var.environment
      managed_by  = "opentofu"
    },
    var.tags
  )
}
