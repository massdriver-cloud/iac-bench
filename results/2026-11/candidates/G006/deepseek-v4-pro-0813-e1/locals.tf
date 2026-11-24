locals {
  normalized_name        = lower(replace(var.name, "-", ""))
  normalized_environment = lower(replace(var.environment, "-", ""))

  # A deterministic suffix makes collisions far less likely while remaining
  # reproducible in Terraform without depending on another provider.
  name_seed = "${var.resource_group_name}-${var.location}-${var.name}-${var.environment}"

  generated_storage_account_name = substr(
    "st${local.normalized_name}${local.normalized_environment}${substr(md5(local.name_seed), 0, 8)}",
    0,
    24,
  )

  storage_account_name = coalesce(var.storage_account_name, local.generated_storage_account_name)

  default_tags = {
    application = var.name
    environment = var.environment
    managed_by  = "opentofu"
  }
}
