module "application_storage" {
  source = "../.."

  application_name         = "orders"
  resource_group_name      = "orders-staging"
  application_principal_id = "00000000-0000-0000-0000-000000000001"

  containers = ["uploads", "media", "reports", "exports"]

  tags = {
    environment = "staging"
  }
}

output "blob_endpoint" {
  value = module.application_storage.primary_blob_endpoint
}

output "containers" {
  value = module.application_storage.container_names
}
