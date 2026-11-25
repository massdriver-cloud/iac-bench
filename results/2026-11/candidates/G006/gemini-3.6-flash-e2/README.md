# Azure Storage Account Standard Module

A standardized OpenTofu root module for application teams deploying storage accounts for their applications running on AKS and Azure App Service.

## Features & Secure Defaults

- **TLS 1.2 Enforcement**: Secure transit only with minimum TLS 1.2.
- **Entra ID Access Control**: Integration with application Entra ID / Managed Identities (AKS Workload Identity, App Service Managed Identity) using Azure RBAC roles (`Storage Blob Data Contributor` by default).
- **Blob Public Access Disabled**: Public access to nested blobs/containers is disabled by default for data privacy.
- **Data Retention & Soft Delete**: 7-day soft delete retention policy for blobs and containers, plus blob versioning enabled by default.
- **Container Provisioning**: Easily define application containers (e.g., `user-uploads`, `generated-reports`) with default private access.
- **Lifecycle Management & Network Rules**: Optional auto-tiering policies and network access rules.

## Quickstart / Minimal Example

For application developers who want sensible defaults:

```hcl
module "app_storage" {
  source              = "./"
  name                = "stordersstaging"
  resource_group_name = "orders-staging"
}
```

## Advanced Usage Example

For applications configuring custom containers, Entra ID principal access, and lifecycle rules:

```hcl
module "app_storage" {
  source              = "./"
  name                = "stordersprod"
  resource_group_name = "orders-prod"
  location            = "eastus"

  # Container creation
  containers = [
    "user-uploads",
    "media-assets",
    "monthly-reports"
  ]

  # Grant application identities (AKS Workload Identity / App Service MI) access
  principal_ids = [
    "11111111-1111-1111-1111-111111111111" # App Service / Workload Identity Principal ID
  ]
  role_definition_name = "Storage Blob Data Contributor"

  # Automated lifecycle policies
  lifecycle_rules = [
    {
      name    = "archive-old-reports"
      enabled = true
      filters = {
        prefix_match = ["monthly-reports/"]
        blob_types   = ["blockBlob"]
      }
      actions = {
        base_blob = {
          tier_to_cool_after_days_since_modification_greater_than    = 30
          tier_to_archive_after_days_since_modification_greater_than = 90
          delete_after_days_since_modification_greater_than          = 365
        }
      }
    }
  ]

  tags = {
    Environment = "prod"
    Application = "orders"
    ManagedBy   = "OpenTofu"
  }
}
```

## Input Variables

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `name` | `string` | *Required* | Globally unique storage account name (3-24 lowercase alphanumeric). |
| `resource_group_name` | `string` | *Required* | Target resource group name. |
| `location` | `string` | `"eastus"` | Azure region. |
| `account_tier` | `string` | `"Standard"` | Tier (`Standard` or `Premium`). |
| `account_replication_type` | `string` | `"LRS"` | Replication type (`LRS`, `ZRS`, `GRS`, etc.). |
| `access_tier` | `string` | `"Hot"` | Access tier (`Hot` or `Cool`). |
| `containers` | `list(string)` | `[]` | List of container names to provision. |
| `principal_ids` | `list(string)` | `[]` | Entra ID principal IDs to grant storage access. |
| `role_definition_name` | `string` | `"Storage Blob Data Contributor"` | Azure RBAC role definition for `principal_ids`. |
| `allow_blob_public_access` | `bool` | `false` | Disable or allow public blob access. |
| `blob_versioning_enabled` | `bool` | `true` | Enable blob versioning. |
| `blob_soft_delete_retention_days` | `number` | `7` | Retention days for deleted blobs. |
| `container_soft_delete_retention_days` | `number` | `7` | Retention days for deleted containers. |
| `lifecycle_rules` | `list` | `[]` | Lifecycle management policy rules. |
| `tags` | `map(string)` | `{}` | Tags to assign to the storage account. |

## Outputs

| Name | Description |
|------|-------------|
| `id` | Resource ID of the storage account. |
| `name` | Storage account name. |
| `primary_blob_endpoint` | Primary blob service endpoint URL. |
| `primary_blob_host` | Primary blob host name. |
| `primary_access_key` | Primary access key (sensitive). |
| `primary_connection_string` | Primary connection string (sensitive). |
| `containers` | Details of created containers. |
| `role_assignments` | Details of created role assignments. |
