# Development smoke test - not part of the module's interface.
#
# Exercises every optional code path (production resource-group inference,
# identity grants, file shares, private endpoints, diagnostics) in one plan:
#
#   tofu plan -var-file=probe.tfvars
#
# Safe to delete.
name                       = "orders"
resource_group_name        = "orders-prod"
principal_id               = "00000000-0000-0000-0000-000000000000"
containers                 = ["uploads", "reports"]
file_shares                = { content = 100 }
private_endpoint_subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/orders-prod/providers/Microsoft.Network/virtualNetworks/aks-vnet/subnets/private-endpoints"
log_analytics_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/orders-prod/providers/Microsoft.OperationalInsights/workspaces/app-logs"
