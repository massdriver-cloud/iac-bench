locals {
  is_prod = var.environment == "prod"

  sanitized_app_env    = replace(lower("${var.application_name}${var.environment}"), "/[^a-z0-9]/", "")
  storage_name_prefix  = substr("st${local.sanitized_app_env}", 0, 18)
  storage_account_name = "${local.storage_name_prefix}${random_string.suffix.result}"

  replication_type           = coalesce(var.replication_type, local.is_prod ? "GRS" : "LRS")
  soft_delete_retention_days = coalesce(var.soft_delete_retention_days, local.is_prod ? 30 : 7)

  use_private_endpoint          = var.private_endpoint_subnet_id != null
  restrict_network              = length(var.allowed_subnet_ids) > 0 || length(var.allowed_ip_ranges) > 0
  public_network_access_enabled = !local.use_private_endpoint

  contributor_principal_ids = toset(concat([var.app_identity_principal_id], var.additional_contributor_principal_ids))
  reader_principal_ids      = toset(var.reader_principal_ids)

  container_lifecycle_rules = {
    for name, cfg in var.containers : name => cfg
    if cfg.cool_after_days != null || cfg.expire_after_days != null
  }
  create_management_policy = var.versioning_enabled || length(local.container_lifecycle_rules) > 0

  common_tags = merge(
    {
      application = var.application_name
      environment = var.environment
      managed_by  = "opentofu"
    },
    var.tags
  )
}
