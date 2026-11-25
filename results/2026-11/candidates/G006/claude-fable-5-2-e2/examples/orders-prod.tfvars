# Example: storage for the "orders" application in production.
# Copy this file, change the values, and run:
#
#   tofu plan  -var-file=orders-prod.tfvars
#   tofu apply -var-file=orders-prod.tfvars
#
# The storage account is created in the application's existing resource group,
# "orders-prod" (<application>-<environment>).

application = "orders"
environment = "prod"

# Object ID of the identity the application runs as (the managed identity used
# by the AKS workload / App Service). Find it with:
#   az identity show -g orders-prod -n <identity name> --query principalId -o tsv
application_principal_id = "7c9e6679-7425-40de-944b-e07fc1f90ae7"

# One container per kind of file. Reports and exports clean themselves up.
containers = {
  uploads = {}
  media   = {}
  reports = { delete_after_days = 90 }
  exports = { delete_after_days = 30 }
}

# The subnet(s) the application runs in. Nothing else can reach the storage.
allowed_subnet_ids = [
  "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/network-prod/providers/Microsoft.Network/virtualNetworks/vnet-prod/subnets/aks-nodes",
]

# Only if browsers upload/download directly using links handed out by the backend.
# cors_allowed_origins = ["https://orders.example.com"]
