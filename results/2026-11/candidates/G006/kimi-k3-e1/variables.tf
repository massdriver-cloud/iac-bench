# ---------------------------------------------------------------------------
# Required inputs — the only things an app team must supply.
# ---------------------------------------------------------------------------

variable "app_name" {
  type        = string
  description = "Short identifier for the application (e.g. \"orders\"). Used in the storage account name and tags. 1-9 characters: lowercase letters, digits and hyphens, starting and ending with a letter or digit."

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{0,7}[a-z0-9])?$", var.app_name))
    error_message = "app_name must be 1-9 characters of lowercase letters, digits and hyphens, starting and ending with a letter or digit (e.g. \"orders\", \"billing-api\")."
  }
}

variable "environment" {
  type        = string
  description = "Environment name (e.g. \"staging\", \"prod\"). Used in the storage account name and tags. 1-7 lowercase letters or digits. \"prod\" upgrades the default redundancy from LRS to ZRS."

  validation {
    condition     = can(regex("^[a-z0-9]{1,7}$", var.environment))
    error_message = "environment must be 1-7 characters of lowercase letters and digits (e.g. dev, staging, prod)."
  }
}

variable "resource_group_name" {
  type        = string
  description = "Name of the application's existing resource group (e.g. \"orders-staging\"). The module does not create resource groups; every application already has one per environment."

  validation {
    condition     = length(trimspace(var.resource_group_name)) > 0
    error_message = "resource_group_name must not be empty."
  }
}

variable "location" {
  type        = string
  description = "Azure region for the storage account (e.g. \"westeurope\"). Use the same region as the application's resource group."

  validation {
    condition     = length(trimspace(var.location)) > 0
    error_message = "location must not be empty."
  }
}

variable "app_identity_principal_id" {
  type        = string
  description = "Object (principal) ID of the application's Entra ID identity — the managed identity used by the AKS workload / App Service, or its service principal. This is the *object ID*, not the application (client) ID. The identity is granted Storage Blob Data Contributor on the account."

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.app_identity_principal_id))
    error_message = "app_identity_principal_id must be a UUID. Use the identity's object ID (e.g. from the managed identity blade), not the application (client) ID."
  }
}

# ---------------------------------------------------------------------------
# Optional inputs — sensible module defaults apply unless overridden.
# ---------------------------------------------------------------------------

variable "containers" {
  type        = set(string)
  default     = []
  description = "Blob containers to create, e.g. [\"uploads\", \"reports\"]. All containers are private; anonymous access is never enabled. Names must follow container naming rules (3-63 chars, lowercase letters, digits, hyphens)."

  validation {
    condition = alltrue([
      for name in var.containers : can(regex("^[a-z0-9]([a-z0-9-]{1,61}[a-z0-9])?$", name))
    ])
    error_message = "Each container name must be 3-63 characters of lowercase letters, digits and hyphens, starting and ending with a letter or digit."
  }
}

variable "account_replication_type" {
  type        = string
  default     = null
  description = "Storage redundancy: LRS, ZRS, GRS, RAGRS, GZRS or RAGZRS. Defaults to ZRS in \"prod\" and LRS everywhere else."

  validation {
    condition     = var.account_replication_type == null || contains(["LRS", "ZRS", "GRS", "RAGRS", "GZRS", "RAGZRS"], var.account_replication_type)
    error_message = "account_replication_type must be one of LRS, ZRS, GRS, RAGRS, GZRS, RAGZRS."
  }
}

variable "soft_delete_retention_days" {
  type        = number
  default     = 7
  description = "Number of days deleted blobs and containers can be restored (soft delete)."

  validation {
    condition     = var.soft_delete_retention_days >= 1 && var.soft_delete_retention_days <= 365
    error_message = "soft_delete_retention_days must be between 1 and 365."
  }
}

variable "shared_access_key_enabled" {
  type        = bool
  default     = false
  description = "Allow shared key / connection string / account SAS authorization. Disabled by default: applications authenticate with their Entra identity via RBAC. Enable only for legacy clients that cannot use Entra ID."
}

variable "network_allowed_subnet_ids" {
  type        = list(string)
  default     = []
  description = "Subnet resource IDs allowed to reach the account, e.g. the AKS node subnet or the App Service VNet-integration subnet (the subnet needs the Microsoft.Storage service endpoint). Setting any subnet or IP rule switches the firewall default action to Deny."

  validation {
    condition     = alltrue([for id in var.network_allowed_subnet_ids : can(regex("^/subscriptions/", id))])
    error_message = "network_allowed_subnet_ids entries must be full subnet resource IDs starting with \"/subscriptions/\"."
  }
}

variable "network_allowed_ip_rules" {
  type        = list(string)
  default     = []
  description = "Public IPv4 addresses or CIDR ranges allowed to reach the account. Setting any IP or subnet rule switches the firewall default action to Deny."

  validation {
    condition     = alltrue([for ip in var.network_allowed_ip_rules : can(regex("^\\d{1,3}(\\.\\d{1,3}){3}(/\\d{1,2})?$", ip))])
    error_message = "network_allowed_ip_rules entries must be IPv4 addresses or CIDR ranges (e.g. \"203.0.113.10\" or \"203.0.113.0/24\")."
  }
}

variable "name_override" {
  type        = string
  default     = null
  description = "Full storage account name, replacing the generated one. Must be globally unique: 3-24 lowercase letters and digits. Prefer the generated name unless you must match an existing convention."

  validation {
    condition     = var.name_override == null || can(regex("^[a-z0-9]{3,24}$", var.name_override))
    error_message = "name_override must be 3-24 characters of lowercase letters and digits (storage account naming rules)."
  }
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Extra tags, merged over the module's standard tags (application, environment, managed-by)."
}
