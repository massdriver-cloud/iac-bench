locals {
  ###############################################################################
  # Naming
  #
  # Storage account names are a global namespace of at most 24 lower-case
  # alphanumeric characters. We derive one deterministically from the
  # application and resource group names, so nobody has to invent a unique
  # name, no two environments of one application collide, and re-running this
  # module always yields the same account.
  ###############################################################################
  app_label = substr(replace(lower(var.name), "/[^a-z0-9]/", ""), 0, 16)

  storage_account_name = substr("st${local.app_label}${substr(sha256("${var.name}|${var.resource_group_name}"), 0, 6)}", 0, 24)

  ###############################################################################
  # Environment
  #
  # Resource groups follow <application>-<environment> (orders-staging,
  # orders-prod), which is the only environment signal the platform gives us.
  # Production accounts get zone redundancy; everything else pays for LRS.
  ###############################################################################
  is_production = can(regex("(^|[-_])prod(uction)?($|[-_])", lower(var.resource_group_name)))

  replication_type = coalesce(var.replication_type, local.is_production ? "ZRS" : "LRS")

  # Teams usually don't know their resource group's region off-hand; the
  # resource group does. `location` still wins when supplied.
  location = coalesce(
    var.location,
    try(data.azurerm_resource_group.this[0].location, null)
  )

  ###############################################################################
  # Networking
  ###############################################################################
  private_endpoints_enabled = var.private_endpoint_subnet_id != null

  public_network_access_enabled = (
    var.public_network_access_enabled != null
    ? var.public_network_access_enabled
    : !local.private_endpoints_enabled
  )

  network_rules_restricting = length(var.allowed_ip_cidrs) > 0 || length(var.allowed_subnet_ids) > 0

  # Open-but-authenticated by default; Deny as soon as any rule exists or the
  # public endpoint is turned off.
  network_default_action = (
    local.public_network_access_enabled && !local.network_rules_restricting
    ? "Allow"
    : "Deny"
  )

  # /subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.Network/virtualNetworks/<vnet>/subnets/<subnet>
  subnet_id_parts = var.private_endpoint_subnet_id == null ? [] : split("/", var.private_endpoint_subnet_id)

  virtual_network_id = (
    var.private_endpoint_subnet_id == null
    ? null
    : join("/", slice(local.subnet_id_parts, 0, 9))
  )

  ###############################################################################
  # Tags
  ###############################################################################
  tags = merge({ application = var.name }, var.tags)
}
