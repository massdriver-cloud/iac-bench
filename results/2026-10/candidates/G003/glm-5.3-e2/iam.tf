# -----------------------------------------------------------------------------
# Registry access: when pulling with the managed identity and an ACR resource
# id is given, grant AcrPull to the app and to every slot (each has its own
# system-assigned identity). After a first apply that adds the grant, restart
# the app once so App Service re-syncs registry credentials.
# -----------------------------------------------------------------------------

resource "azurerm_role_assignment" "acr_pull" {
  for_each = local.grant_acr_pull ? local.acr_pull_principals : {}

  scope                = var.image.registry_id
  role_definition_name = "AcrPull"
  principal_id         = each.value
}
