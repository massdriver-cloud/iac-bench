# Extended example (not auto-loaded): exercises every optional knob.
# Used to verify the module plans cleanly beyond the minimal instantiation.
# See minimal.tfvars for the smallest valid instantiation.

app_name              = "orders"
environment           = "prod"
resource_group_name   = "orders-prod"
identity_principal_id = "11111111-1111-1111-1111-111111111111"
location              = "westeurope"

containers       = ["uploads", "reports"]
replication_type = "ZRS"

lifecycle_rules = [
  {
    name              = "expire-exports"
    prefixes          = ["reports/"]
    delete_after_days = 90
  },
  {
    name                       = "cool-old-uploads"
    prefixes                   = ["uploads/"]
    tier_to_cool_after_days    = 30
    tier_to_archive_after_days = 180
    snapshot_delete_after_days = 30
  },
]

network = {
  default_action = "Deny"
  ip_rules       = ["203.0.113.10"]
}

tags = {
  cost-center = "team-orders"
}
