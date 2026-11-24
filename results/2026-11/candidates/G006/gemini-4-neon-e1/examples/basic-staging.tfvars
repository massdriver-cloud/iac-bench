# Basic staging example — copy this file, replace the values below, and apply.
# The module automatically handles naming, Entra ID authentication (no shared keys),
# private containers, TLS 1.2+, soft delete, blob versioning, and noncurrent version cleanup.

application_name         = "orders"
environment              = "staging"
resource_group_name      = "orders-staging"
location                 = "eastus2"
application_principal_id = "11111111-2222-3333-4444-555555555555"

containers = {
  uploads = {}
  media = {
    tier_to_cool_after_days = 90
  }
  reports = {
    delete_after_days = 30
  }
}

# Optional: allow your AKS or App Service VNet subnet via Service Endpoints.
# allowed_subnet_ids = [
#   "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/network-staging/providers/Microsoft.Network/virtualNetworks/vnet-staging/subnets/snet-aks"
# ]

owner       = "orders-team"
cost_center = "cc-4200"
