resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

locals {
  # Clean up the name to contain only lowercase letters and numbers
  clean_name = lower(replace("${var.application_name}${var.environment}", "/[^a-zA-Z0-9]/", ""))
  
  # A storage account name must be 3-24 characters.
  # We use up to 18 characters from the clean_name and 6 random characters.
  sa_name = "${substr(local.clean_name, 0, 18)}${random_string.suffix.result}"
}

resource "azurerm_storage_account" "app_storage" {
  name                     = local.sa_name
  resource_group_name      = var.resource_group_name
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = var.environment == "prod" ? "ZRS" : "LRS"

  # Security best practices
  min_tls_version                 = "TLS1_2"
  https_traffic_only_enabled      = true
  allow_nested_items_to_be_public = false
  
  tags = {
    Application = var.application_name
    Environment = var.environment
  }
}

resource "azurerm_storage_container" "app_containers" {
  for_each              = var.containers
  name                  = each.key
  storage_account_name  = azurerm_storage_account.app_storage.name
  container_access_type = "private"
}

resource "azurerm_role_assignment" "app_data_contributor" {
  scope                = azurerm_storage_account.app_storage.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = var.app_identity_principal_id
  
  skip_service_principal_aad_check = true
}
