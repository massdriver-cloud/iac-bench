# ---------------------------------------------------------------------------
# Naming and tagging
# ---------------------------------------------------------------------------

locals {
  # Storage account names must be 3-24 lowercase alphanumerics and globally
  # unique. Convention: "st" + application + environment + random suffix,
  # e.g. "stordersstagingk7d2".
  safe_application = replace(lower(var.application), "/[^a-z0-9]/", "")
  safe_environment = replace(lower(var.environment), "/[^a-z0-9]/", "")

  account_name = format("st%s%s%s",
    substr(local.safe_application, 0, 10),
    substr(local.safe_environment, 0, 8),
    random_string.account_suffix.result,
  )

  default_tags = {
    application = var.application
    environment = var.environment
    module      = "app-storage"
    managed-by  = "opentofu"
  }
  tags = merge(local.default_tags, var.additional_tags)
}

resource "random_string" "account_suffix" {
  length  = 4
  lower   = true
  upper   = false
  numeric = true
  special = false
}

# ---------------------------------------------------------------------------
# Resource group: use the application's existing one, or create the
# conventional "<application>-<environment>" group when it does not exist yet.
# ---------------------------------------------------------------------------

resource "azurerm_resource_group" "this" {
  count = var.resource_group_name == null ? 1 : 0

  name     = "${lower(var.application)}-${lower(var.environment)}"
  location = var.location
  tags     = local.tags

  lifecycle {
    precondition {
      condition     = var.location != null
      error_message = "Set `location` when not providing an existing `resource_group_name`, so the module knows where to create the resource group."
    }
  }
}

data "azurerm_resource_group" "existing" {
  count = var.resource_group_name != null && var.location == null ? 1 : 0

  name = var.resource_group_name
}

locals {
  resource_group_name = var.resource_group_name != null ? var.resource_group_name : azurerm_resource_group.this[0].name

  # Explicit location wins; otherwise inherit the resource group's region.
  location = (
    var.location != null ? var.location :
    var.resource_group_name != null ? data.azurerm_resource_group.existing[0].location :
    azurerm_resource_group.this[0].location
  )
}
