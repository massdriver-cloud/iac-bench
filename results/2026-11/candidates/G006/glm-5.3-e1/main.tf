# =============================================================================
# Location and naming
# =============================================================================

# The application's resource group is the source of truth for where its
# storage lives. We only need to read it when `location` is not set explicitly.
data "azurerm_resource_group" "app" {
  count = var.location == null ? 1 : 0

  name = var.resource_group_name
}

# Storage account names are global across all of Azure, must be 3-24
# characters of lower-case letters and digits, and are the one name an app
# team should never have to invent. We derive a readable prefix from the
# application's resource group and append a short random suffix so that two
# applications (or a re-created account) can never collide.
resource "random_id" "account_suffix" {
  byte_length = 4
}

locals {
  # Either the region the team asked for, or the region their resource
  # group already lives in.
  location = coalesce(
    var.location,
    one(data.azurerm_resource_group.app[*].location),
  )

  # "orders-staging" -> "stordersstaging<random>" (<= 24 chars, valid).
  name_base = lower(replace(
    var.account_name_prefix != null ? var.account_name_prefix : var.resource_group_name,
    "/[^a-zA-Z0-9]/",
    "",
  ))

  storage_account_name = format(
    "st%s%s",
    substr(local.name_base, 0, 14),
    random_id.account_suffix.hex,
  )

  # Emit a network_rules block only when something is actually being
  # restricted; with the defaults (public access allowed, no rules) an empty
  # rules set would be noise.
  network_rules_needed = (
    length(var.allowed_ip_ranges) > 0 ||
    length(var.allowed_subnet_ids) > 0 ||
    !var.public_network_access_enabled
  )

  common_tags = merge({ managed-by = "opentofu" }, var.tags)
}
