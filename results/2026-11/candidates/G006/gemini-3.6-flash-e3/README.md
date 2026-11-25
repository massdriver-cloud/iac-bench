# Standard Azure Storage Account OpenTofu Module

This reusable OpenTofu module provides a standardized, secure, and opinionated Azure Storage Account configuration for application teams operating on Azure Kubernetes Service (AKS) and Azure App Service.

## Key Features & Defaults

- **Security Best Practices**:
  - Requires **TLS 1.2** (`min_tls_version = "TLS1_2"`).
  - Enforces **HTTPS** only traffic.
  - Disables public access for nested blobs/containers by default (`allow_nested_items_to_be_public = false`).
  - Defaults to **OAuth / Entra ID authentication** for Azure portal browsing (`default_to_oauth_authentication = true`).
- **Data Protection**:
  - Enables **Blob Versioning** by default (`enable_versioning = true`).
  - Enables **Blob Soft Delete** (7 days retention by default).
  - Enables **Container Soft Delete** (7 days retention by default).
- **Entra ID Integration**:
  - Seamless RBAC role assignment (`Storage Blob Data Contributor`) for application managed identities (AKS Workload Identity or App Service Managed Identity) via `principal_ids`.
- **Developer Simplicity**:
  - Developers only need to provide the `storage_account_name` and `resource_group_name`.
  - Storage containers (`containers = ["uploads", "images", "reports"]`), queues, tables, and file shares can be specified via simple lists.

## Minimal Usage Example

```hcl
module "app_storage" {
  source = "./"

  storage_account_name = "stordersstaging001"
  resource_group_name  = "orders-staging"
}
```

## Complete Usage Example

```hcl
module "app_storage" {
  source = "./"

  storage_account_name = "stordersprod001"
  resource_group_name  = "orders-prod"
  location             = "eastus"

  # Containers for app uploads and exports
  containers = ["user-uploads", "product-images", "reports"]

  # Entra ID principal IDs (AKS Workload Identity / App Service Managed Identity)
  principal_ids = [
    "00000000-0000-0000-0000-000000000000"
  ]

  tags = {
    Environment = "prod"
    Application = "orders"
  }
}
```
