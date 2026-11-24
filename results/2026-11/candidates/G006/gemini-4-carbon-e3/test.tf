check "storage_account_naming_invariant" {
  assert {
    condition     = can(regex("^[a-z0-9]{3,24}$", azurerm_storage_account.this.name))
    error_message = "Resolved storage account name must be 3 to 24 lowercase alphanumeric characters."
  }
}

check "zero_shared_keys_and_no_public_blobs" {
  assert {
    condition = (
      azurerm_storage_account.this.shared_access_key_enabled == false &&
      azurerm_storage_account.this.allow_nested_items_to_be_public == false &&
      azurerm_storage_account.this.https_traffic_only_enabled == true &&
      azurerm_storage_account.this.min_tls_version == "TLS1_2"
    )
    error_message = "Storage account must enforce TLS 1.2+, HTTPS-only traffic, disabled anonymous blob access, and disabled shared access keys."
  }
}
