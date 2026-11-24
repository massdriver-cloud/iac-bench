name                = "stordersstaging"
resource_group_name = "orders-staging"
location            = "eastus"

containers = [
  "user-uploads",
  "media",
  "reports"
]

principal_ids = [
  "11111111-1111-1111-1111-111111111111"
]

role_definition_name = "Storage Blob Data Contributor"

role_assignments = {
  reader = {
    principal_id         = "22222222-2222-2222-2222-222222222222"
    role_definition_name = "Storage Blob Data Reader"
  }
}

lifecycle_rules = [
  {
    name    = "cleanup-old-reports"
    enabled = true
    filters = {
      prefix_match = ["reports/"]
      blob_types   = ["blockBlob"]
    }
    actions = {
      base_blob = {
        tier_to_cool_after_days_since_modification_greater_than = 30
        delete_after_days_since_modification_greater_than       = 90
      }
    }
  }
]

tags = {
  Environment = "staging"
  Application = "orders"
}
