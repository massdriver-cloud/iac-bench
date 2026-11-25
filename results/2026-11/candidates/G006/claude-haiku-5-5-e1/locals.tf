locals {
  # Per-environment policy. Developers never set these; the module decides.
  env_profile = {
    dev = {
      env_code         = "dev"
      replication_type = "LRS"
      soft_delete_days = 7
      deletion_lock    = false
    }
    staging = {
      env_code         = "stg"
      replication_type = "LRS"
      soft_delete_days = 14
      deletion_lock    = false
    }
    prod = {
      env_code         = "prd"
      replication_type = "GRS"
      soft_delete_days = 30
      deletion_lock    = true
    }
  }

  profile = local.env_profile[var.environment]

  resource_group_name = coalesce(var.resource_group_name, "${var.application_name}-${var.environment}")

  # Storage account names: 3-24 chars, lowercase letters and digits, globally unique.
  # "st"(2) + app(<=11) + env code(3) + random suffix(6) = <=22 chars.
  storage_account_name = "st${var.application_name}${local.profile.env_code}${random_string.suffix.result}"

  standard_containers = ["uploads", "media", "reports", "exports"]
  containers          = distinct(concat(local.standard_containers, var.additional_containers))

  # Generated and exported files are rarely read after a few weeks; move them to cool.
  cool_after_days_prefixes = ["reports/", "exports/"]

  tags = merge(var.tags, {
    application = var.application_name
    environment = var.environment
    managed-by  = "opentofu"
  })
}
