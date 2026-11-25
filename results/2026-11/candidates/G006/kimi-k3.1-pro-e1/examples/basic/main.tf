# Copy this configuration alongside the module, then replace the four required
# values. container_names is optional and defaults to ["files"].
module "application_storage" {
  source = "../.."

  application_name                  = "orders"
  resource_group_name               = "orders-staging"
  location                          = "eastus"
  application_identity_principal_id = "11111111-1111-1111-1111-111111111111"

  container_names = ["uploads", "media", "reports"]

  tags = {
    environment = "staging"
    owner       = "orders-team"
  }
}

output "storage_account_name" {
  value = module.application_storage.storage_account_name
}

output "blob_endpoint" {
  value = module.application_storage.primary_blob_endpoint
}

output "containers" {
  value = module.application_storage.containers
}
