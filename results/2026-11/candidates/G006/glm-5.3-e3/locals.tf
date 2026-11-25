locals {
  # Storage belongs in the application's resource group, so by default it sits
  # in the same region as that resource group.
  location = coalesce(
    var.location,
    try(data.azurerm_resource_group.this[0].location, null),
  )

  environment_abbreviation = {
    dev     = "dev"
    test    = "tst"
    staging = "stg"
    prod    = "prd"
  }[var.environment]

  # Storage account names must be globally unique across all of Azure, 3-24
  # characters, lowercase letters and digits only. A deterministic suffix
  # derived from the resource group and the workload name keeps names unique
  # AND predictable: the same inputs always produce the same name (including
  # after a destroy/recreate cycle), and different applications or different
  # environments never collide.
  storage_account_name = "${substr(
    "st${replace(var.name, "/[^a-z0-9]/", "")}${local.environment_abbreviation}",
    0,
    16,
  )}${substr(sha256("${var.resource_group_name}/${var.name}"), 0, 8)}"

  # Durability defaults: production data is replicated to a second region,
  # everything else stays local (LRS) to keep the bill down.
  replication_type = coalesce(
    var.replication_type,
    var.environment == "prod" ? "GRS" : "LRS",
  )

  private_endpoints_enabled = length(var.private_endpoint_subnet_ids) > 0

  # Network exposure: as soon as there are private endpoints, the public
  # endpoint is turned off unless the team explicitly wants both. Without
  # private endpoints the account is reachable from the internet, but every
  # request must still authenticate with Entra ID (no keys, no public blobs).
  public_network_access_enabled = coalesce(
    var.public_network_access_enabled,
    !local.private_endpoints_enabled,
  )

  # Tighten the network ACL as soon as there is something meaningful to
  # tighten with: explicit IP restrictions, or private endpoints locking
  # public access off entirely.
  network_rules_required = !local.public_network_access_enabled || length(var.allowed_ip_ranges) > 0

  # Lifecycle settings with defaults filled in, so the management policy
  # always has valid numbers for the rules that are always on.
  blob_lifecycle_days = {
    days_to_cool          = coalesce(var.blob_lifecycle.days_to_cool, 90)
    days_to_archive       = var.blob_lifecycle.days_to_archive
    days_to_delete        = var.blob_lifecycle.days_to_delete
    days_to_keep_versions = coalesce(var.blob_lifecycle.days_to_keep_versions, 90)
  }

  tags = merge(
    {
      application = var.name
      environment = var.environment
      managed-by  = "opentofu"
    },
    var.tags,
  )
}

locals {
  # Private endpoint subnets, keyed by a stable short index (01, 02, ...).
  private_endpoint_subnets = {
    for index, subnet_id in var.private_endpoint_subnet_ids :
    format("%02d", index + 1) => subnet_id
  }

  # Subnet IDs look like
  # /subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.Network/virtualNetworks/<vnet>/subnets/<subnet>
  # so everything before "/subnets/" identifies the virtual network.
  virtual_network_ids = toset([
    for subnet_id in var.private_endpoint_subnet_ids :
    element(split("/subnets/", subnet_id), 0)
  ])

  create_private_dns_zone = local.private_endpoints_enabled && var.private_dns_zone_id == null

  # The private DNS zone the endpoints register in: the organisation's
  # existing zone when one is supplied, otherwise the zone this module
  # creates. Null when private endpoints are not used.
  blob_private_dns_zone_id = var.private_dns_zone_id != null ? var.private_dns_zone_id : try(
    azurerm_private_dns_zone.blob[0].id,
    null,
  )
}
