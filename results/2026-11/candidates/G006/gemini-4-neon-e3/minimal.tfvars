application_name    = "orders"
environment         = "staging"
resource_group_name = "orders-staging"
location            = "eastus2"
app_principal_id    = "11111111-2222-3333-4444-555555555555"

containers = {
  uploads = {}
  reports = {
    retention_days = 90
  }
}
