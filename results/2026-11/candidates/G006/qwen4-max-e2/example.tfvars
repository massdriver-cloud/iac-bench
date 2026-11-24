# Example for a real app team: copy this file, fill in your values.
# Only resource_group_name and name are required.

resource_group_name = "orders-prod" # your app's existing RG for this environment
name                = "orders"      # short app name

# Your app's existing Entra ID managed identity object (principal) IDs —
# e.g. the AKS workload identity and the App Service identity. They get
# 'Storage Blob Data Contributor'; access keys are disabled.
principal_ids = [
  "11111111-1111-1111-1111-111111111111",
]

# Containers for your app's files (all private).
containers = ["uploads", "reports"]

# Allow your AKS / App Service VNet-integration subnet through the
# firewall (enable the Microsoft.Storage service endpoint on it first).
virtual_network_subnet_ids = [
  "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/orders-prod-network/providers/Microsoft.Network/virtualNetworks/orders-prod/subnets/aks",
]

tags = {
  environment = "prod"
  team        = "orders"
  cost-center = "cc-1234"
}
