# Azure Storage Account Module for Applications

A standardized, secure-by-default OpenTofu module for application teams running workloads on Azure Kubernetes Service (AKS) and Azure App Service.

## Overview

This module standardizes Azure Storage provisioning across all application environments (dev, staging, production). Application developers only need to copy an example, provide a couple of obvious inputs (application name, environment, and resource group), and the module handles all Azure Storage architecture, security, and resilience best practices.

## Usage

### Minimal Example (Staging)

```hcl
module "storage" {
  source = "./"

  application_name    = "orders"
  environment         = "staging"
  resource_group_name = "orders-staging"
}
```

### Full Example with AKS / App Service Identity (Production)

```hcl
module "storage" {
  source = "./"

  application_name    = "orders"
  environment         = "prod"
  resource_group_name = "orders-prod"
  location            = "eastus"

  # Entra ID identity of the AKS Workload Identity or App Service Managed Identity
  principal_id = "00000000-0000-0000-0000-000000000000"

  # Custom container list (defaults to ["uploads", "media", "reports"])
  containers = ["uploads", "invoices", "reports"]

  tags = {
    CostCenter = "engineering"
    Team       = "orders-squad"
  }
}
```

## Built-In Architectural Decisions

| Decision | Setting | Rationale |
|---|---|---|
| **Account Kind & Tier** | `StorageV2` / `Standard` | General Purpose v2 is Microsoft's recommended foundation for blob storage. Standard tier offers optimal cost-to-performance for application files (uploads, media, exports). |
| **Replication Strategy** | `ZRS` (prod) / `LRS` (non-prod) | Automatically enables Zone-Redundant Storage in production for high availability across three availability zones, while using Locally-Redundant Storage in non-prod to save costs. |
| **Authentication & RBAC** | Entra ID (Azure AD) | Modern applications on AKS and App Service use Managed Identities and Workload Identity. `Storage Blob Data Contributor` is automatically assigned to the application's identity. |
| **Shared Access Keys** | Disabled (`false` by default) | Eliminates shared credential leakage risk and complies with CIS Azure Benchmarks and Microsoft Defender recommendations. |
| **Transport Security** | `TLS 1.2` min & HTTPS only | Enforces encrypted transport and rejects unencrypted HTTP or legacy TLS versions. |
| **Public Blob Access** | Blocked (`false` by default) | Prevents anonymous data exposure. All containers default to `private`. Access is granted via Entra ID or short-lived SAS tokens. |
| **Data Protection** | Soft delete (7 days) & Versioning | Protects against accidental deletion or overwrite of critical files and reports. |
| **Storage Naming** | Auto-generated compliant name | Azure requires storage names to be 3-24 characters, lowercase alphanumeric, and globally unique. The module generates deterministic, compliant names like `stordersstg2980e`. |

## Inputs

| Name | Type | Description | Default | Required |
|---|---|---|---|---|
| `application_name` | `string` | Name of the application (e.g. `orders`). | n/a | yes |
| `environment` | `string` | Deployment environment (e.g. `staging`, `prod`). | n/a | yes |
| `resource_group_name` | `string` | Name of the existing application resource group (e.g. `orders-staging`). | n/a | yes |
| `location` | `string` | Azure region for the storage account. | `"eastus"` | no |
| `principal_id` | `string` | Entra ID Object ID of the app's Managed Identity / Workload Identity. | `null` | no |
| `principal_ids` | `list(string)` | Additional Entra ID Object IDs to grant contributor access. | `[]` | no |
| `containers` | `list(string)` | Blob container names to create. | `["uploads", "media", "reports"]` | no |
| `shared_access_key_enabled` | `bool` | Whether shared key access is allowed. | `false` | no |
| `replication_type` | `string` | Explicit replication override (e.g. `LRS`, `ZRS`, `GRS`). | `null` (auto-detected) | no |
| `tags` | `map(string)` | Additional resource tags. | `{}` | no |

## Outputs

| Name | Description |
|---|---|
| `storage_account_id` | Resource ID of the storage account. |
| `storage_account_name` | Name of the storage account (e.g. `stordersstg2980e`). |
| `primary_blob_endpoint` | Primary blob endpoint URL (`https://<account>.blob.core.windows.net/`). |
| `container_names` | List of container names created. |
| `containers` | Map of container names to container IDs. |
| `replication_type` | Effective replication type (`ZRS` or `LRS`). |
