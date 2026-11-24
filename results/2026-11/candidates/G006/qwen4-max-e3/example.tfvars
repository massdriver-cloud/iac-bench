# Fuller example: same three required inputs, plus the optional extras.
resource_group_name      = "orders-staging"
environment              = "staging"
application_principal_id = "11111111-1111-1111-1111-111111111111"

blob_containers   = ["uploads", "reports"]
allowed_ip_ranges = ["203.0.113.0/24"]

tags = {
  cost-center = "cc-1234"
  team        = "orders"
}
