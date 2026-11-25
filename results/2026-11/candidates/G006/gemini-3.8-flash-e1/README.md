# Standard Azure Storage Account Module for Applications

This module provides the standard, opinionated, and secure way for application teams running on **Azure Kubernetes Service (AKS)** and **Azure App Service** to provision and consume Azure Storage accounts for application files (user uploads, media, generated reports, exports, etc.).

It is designed specifically for application developers who need reliable, secure storage without having to become Azure Storage experts: simply supply a couple of obvious inputs (`application_name` and `environment`), and trust the module's judgment for architecture, security, and data protection.

---

## Quickstart

### Minimal Example

```hcl
module "storage" {
  source           = "./path-to-module" # or deployed as root module
  application_name = "orders"
  environment      = "staging"
}
```

This single block automatically:
1. Locates the existing `orders-staging` resource group and resolves its region.
2. Generates a globally unique, Azure-compliant storage account name (e.g. `stordersstgin1efa20`).
3. Provisions standard `uploads`, `images`, and `reports` blob containers.
4. Enforces HTTPS only, TLS 1.2, disables anonymous public blob access, and defaults to Microsoft Entra ID authentication.
5. Enables blob versioning and soft delete (7-day retention) for data recovery.
6. Sets cost-efficient `LRS` replication for staging (or high-availability `ZRS` for production).
7. Applies standard tags (`application`, `environment`, `managed-by`).

---

### AKS / App Service with Entra ID Identity

Applications running on AKS (via Azure Workload Identity) or App Service (via Managed Identity) can be granted access automatically by providing their Entra ID principal object ID:

```hcl
module "storage" {
  source                   = "./path-to-module"
  application_name         = "orders"
  environment              = "prod"
  application_principal_id = "00000000-0000-0000-0000-000000000000" # App's Managed Identity Object ID
}
```

The module automatically assigns the application identity the Azure RBAC role `Storage Blob Data Contributor`, granting read, write, and delete permissions to the storage blobs.

---

### Custom Containers & Lifecycle Management

```hcl
module "storage" {
  source           = "./path-to-module"
  application_name = "billing"
  environment      = "prod"

  # Custom container list
  containers = ["invoices", "exports", "attachments"]

  # Enable automated lifecycle management: tier inactive blobs to cool storage
  enable_lifecycle_management = true
  lifecycle_cool_after_days   = 90
  lifecycle_delete_after_days = 365

  # Application identity
  application_principal_id = "00000000-0000-0000-0000-000000000000"
}
```

---

## Design Decisions & Architectural Standards

| Area | Decision | Rationale |
| :--- | :--- | :--- |
| **Naming Convention** | `st<app><env><hash>` | Azure requires 3-24 lowercase alphanumeric characters. The module truncates and sanitizes inputs, appending a deterministic 6-character hash to guarantee global uniqueness without developer guesswork. |
| **Resource Group Alignment** | Defaults to `${application_name}-${environment}` | Automatically places storage in the app's designated resource group (e.g. `orders-staging`, `orders-prod`). Can be overridden if needed. |
| **Location Auto-Detection** | Inherited from Resource Group | Eliminates region mismatches and avoids developer configuration errors. |
| **Environment Redundancy** | Non-prod: `LRS`, Prod: `ZRS` | Cost-effective locally redundant storage for staging/dev; zone-redundant storage for production to withstand availability zone failures. |
| **Anonymous Access** | Disabled (`allow_nested_items_to_be_public = false`) | Zero anonymous public blob access. Prevents data leaks. All requests require Entra ID or signed SAS tokens. |
| **Modern Authentication** | Entra ID OAuth default | Applications on AKS and App Service authenticate using managed identities. Portal and tools default to OAuth. Shared keys remain enabled for tool compatibility. |
| **Transport Security** | TLS 1.2 minimum & HTTPS only | Enforces encrypted transit across all connections. |
| **Data Protection** | Versioning & Soft Delete (7 days) | Protects user uploads, images, and reports against accidental deletion or overwrite. |
| **Standard Containers** | `uploads`, `images`, `reports` | Pre-created out of the box so developers can start storing files immediately. |
| **Network Security** | Bypass for `AzureServices` | Allows seamless connectivity from AKS and App Service workloads, with support for IP/Subnet whitelisting. |

---

## Inputs

| Name | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `application_name` | `string` | **Required** | Application name (e.g. `orders`). Used for naming and tagging. |
| `environment` | `string` | **Required** | Deployment environment (e.g. `staging`, `prod`). Controls replication and naming. |
| `resource_group_name` | `string` | `null` | Resource group name. Defaults to `{application_name}-{environment}`. |
| `location` | `string` | `null` | Azure region. Defaults to the resource group's location. |
| `storage_account_name` | `string` | `null` | Custom storage account name. Defaults to standard generated name. |
| `account_tier` | `string` | `"Standard"` | Storage tier (`Standard` or `Premium`). |
| `account_replication_type` | `string` | `null` | Replication type (`LRS`, `ZRS`, `GRS`). Defaults to `ZRS` for prod, `LRS` for non-prod. |
| `access_tier` | `string` | `"Hot"` | Default blob tier (`Hot` or `Cool`). |
| `containers` | `list(string)` | `["uploads", "images", "reports"]` | Container names to provision. |
| `custom_containers` | `map(object)` | `{}` | Custom container definitions (for custom access types/metadata). |
| `application_principal_id` | `string` | `null` | Entra ID object ID of the app's managed identity or service principal. |
| `application_principal_ids` | `list(string)` | `[]` | Additional Entra ID principal IDs to grant blob access. |
| `role_definition_name` | `string` | `"Storage Blob Data Contributor"` | RBAC role assigned to the application identities. |
| `custom_role_assignments` | `map(object)` | `{}` | Additional custom role assignments. |
| `enable_blob_versioning` | `bool` | `true` | Enable blob versioning for accidental overwrite protection. |
| `blob_soft_delete_retention_days` | `number` | `7` | Retention days for soft-deleted blobs. |
| `container_soft_delete_retention_days` | `number` | `7` | Retention days for soft-deleted containers. |
| `enable_lifecycle_management` | `bool` | `false` | Enable automated blob lifecycle tiering policy. |
| `lifecycle_cool_after_days` | `number` | `90` | Days after modification to tier blobs to Cool storage. |
| `lifecycle_delete_after_days` | `number` | `null` | Days after modification to delete blobs (if set). |
| `network_rules_default_action` | `string` | `"Allow"` | Default network rule action (`Allow` or `Deny`). |
| `network_bypass` | `list(string)` | `["AzureServices"]` | Traffic bypassing network rules. |
| `allowed_ip_ranges` | `list(string)` | `[]` | Allowed public IP addresses / CIDRs. |
| `allowed_subnet_ids` | `list(string)` | `[]` | Allowed VNet subnet resource IDs. |
| `tags` | `map(string)` | `{}` | Additional resource tags. |

---

## Outputs

| Name | Description |
| :--- | :--- |
| `storage_account_id` | Resource Manager ID of the storage account. |
| `storage_account_name` | Name of the storage account. |
| `primary_blob_endpoint` | Primary blob service URL (e.g. `https://<account>.blob.core.windows.net/`) for Azure SDK clients. |
| `primary_blob_host` | Primary blob service hostname. |
| `resource_group_name` | Name of the containing resource group. |
| `location` | Azure region of the storage account. |
| `containers` | Map of created containers with their IDs, names, and access URLs. |
| `container_names` | List of container names created. |
| `assigned_role_principals` | List of Entra ID principal IDs granted blob access. |
| `primary_access_key` | Primary shared access key (sensitive). |
| `primary_connection_string` | Primary connection string (sensitive). |
