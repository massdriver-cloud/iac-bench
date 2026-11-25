locals {
  # Storage account names must be globally unique, 3-24 chars, lowercase
  # alphanumeric. We derive a deterministic name from application+environment
  # so every environment of an application has a predictable, stable name.
  raw_account_name     = replace(lower("${var.application}${var.environment}"), "/[^a-z0-9]/", "")
  storage_account_name = substr("st${local.raw_account_name}", 0, 24)

  # The application's storage lives in its own resource group; by convention
  # that is "<application>-<environment>" (e.g. "orders-staging").
  resource_group_name = coalesce(var.resource_group_name, "${var.application}-${var.environment}")

  # Normalise "West Europe" -> "westeurope".
  location = lower(replace(var.location, " ", ""))

  # Module's judgment on durability: zone-redundant storage for production,
  # locally-redundant (cheaper) everywhere else. Overridable.
  replication_type = coalesce(var.replication_type, startswith(var.environment, "prod") ? "ZRS" : "LRS")

  tags = merge(
    {
      application = var.application
      environment = var.environment
      managed_by  = "opentofu"
    },
    var.tags,
  )
}

# Warn (don't fail) when the derived storage account name had to be truncated
# to Azure's 24-character limit - truncated names are more likely to collide.
check "storage_account_name_not_truncated" {
  assert {
    condition     = length(local.raw_account_name) + 2 <= 24
    error_message = "The storage account name \"st${local.raw_account_name}\" exceeds Azure's 24 character limit and will be truncated to \"${local.storage_account_name}\". Prefer shorter application/environment values to keep names unique."
  }
}
