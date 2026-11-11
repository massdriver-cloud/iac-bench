data "azurerm_client_config" "current" {}

locals {
  tags = merge(var.tags, {
    service    = var.name
    managed-by = "opentofu"
  })

  resource_group_name = var.resource_group_name != null ? data.azurerm_resource_group.existing[0].name : azurerm_resource_group.this[0].name
  resource_group_id   = var.resource_group_name != null ? data.azurerm_resource_group.existing[0].id : azurerm_resource_group.this[0].id

  # Web app names are global DNS names. A short suffix derived from the subscription and resource
  # group keeps "app-orders-api" from colliding with somebody else's, while staying stable across runs.
  name_suffix = substr(sha1("${data.azurerm_client_config.current.subscription_id}/${coalesce(var.resource_group_name, "rg-${var.name}")}/${var.name}"), 0, 6)
  app_name    = "app-${var.name}-${local.name_suffix}"

  # "registry.example.io/team/app:1.2.3" -> host + "team/app:1.2.3"
  registry_host   = split("/", var.image)[0]
  image_name      = trimprefix(var.image, "${local.registry_host}/")
  use_acr         = var.registry.acr_id != null
  acr_name        = local.use_acr ? lower(reverse(split("/", var.registry.acr_id))[0]) : null
  key_vault_name  = var.key_vault != null ? reverse(split("/", var.key_vault.id))[0] : null
  vnet_integrated = var.network.integration_subnet_id != null

  # Access restrictions: listing anything flips the default from allow to deny.
  access_rules = concat(
    [for c in var.network.allowed_cidrs : { name = "allow-${replace(replace(c, "/", "-"), ".", "-")}", ip_address = c, service_tag = null }],
    [for t in var.network.allowed_service_tags : { name = substr("allow-${t}", 0, 32), ip_address = null, service_tag = t }],
  )
  access_default_action = length(local.access_rules) > 0 ? "Deny" : "Allow"

  # HTTP statuses that count as "ready" for the warm-up gates.
  ready_statuses = "200,202,204"

  # The complete environment of a release. Module-managed keys win.
  app_settings = merge(
    var.app_settings,
    var.key_vault == null ? {} : {
      for env, secret in var.key_vault.secrets :
      env => "@Microsoft.KeyVault(VaultName=${local.key_vault_name};SecretName=${secret})"
    },
    {
      WEBSITES_PORT                       = tostring(var.container_port)
      WEBSITES_ENABLE_APP_SERVICE_STORAGE = "false" # stateless containers; no shared /home mount

      # Readiness gates. A container is only put into rotation (on start, scale-out or restart) and a
      # slot is only swapped into production once the health endpoint answers with a success status.
      WEBSITE_WARMUP_PATH               = var.health_check_path
      WEBSITE_WARMUP_STATUSES           = local.ready_statuses
      WEBSITE_SWAP_WARMUP_PING_PATH     = var.health_check_path
      WEBSITE_SWAP_WARMUP_PING_STATUSES = local.ready_statuses

      APPLICATIONINSIGHTS_CONNECTION_STRING = azurerm_application_insights.this.connection_string
      AZURE_CLIENT_ID                       = azurerm_user_assigned_identity.this.client_id # for DefaultAzureCredential in the app
    },
  )
}

# ---------------------------------------------------------------------------------------------
# Resource group
# ---------------------------------------------------------------------------------------------

resource "azurerm_resource_group" "this" {
  count = var.resource_group_name == null ? 1 : 0

  name     = "rg-${var.name}"
  location = var.location
  tags     = local.tags
}

data "azurerm_resource_group" "existing" {
  count = var.resource_group_name != null ? 1 : 0

  name = var.resource_group_name
}

# ---------------------------------------------------------------------------------------------
# Identity
#
# One user-assigned identity per service, shared by production and the staging slot. Because it
# exists before the app does, registry and Key Vault access can be granted before the first container
# pull, and a freshly created staging slot never has to wait for its own role assignments.
# ---------------------------------------------------------------------------------------------

resource "azurerm_user_assigned_identity" "this" {
  name                = "id-${var.name}"
  resource_group_name = local.resource_group_name
  location            = var.location
  tags                = local.tags
}

resource "azurerm_role_assignment" "acr_pull" {
  count = local.use_acr && var.registry.grant_pull ? 1 : 0

  scope                = var.registry.acr_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.this.principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "key_vault_secrets" {
  count = var.key_vault != null ? (var.key_vault.grant_access ? 1 : 0) : 0

  scope                = var.key_vault.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.this.principal_id
  principal_type       = "ServicePrincipal"
}
