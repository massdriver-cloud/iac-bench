# -----------------------------------------------------------------------------
# Required Application Inputs
# -----------------------------------------------------------------------------

variable "app_name" {
  description = "Short application name (e.g. 'orders', 'billing-api'). Used to locate the default '<app_name>-<environment>' resource group, generate a globally unique storage account name, and apply standard resource tags."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{0,38}[a-z0-9]$", var.app_name)) && length(replace(var.app_name, "-", "")) > 0
    error_message = "app_name must be 2 to 40 characters, start and end with a lowercase letter or digit, and contain only lowercase letters, digits, and hyphens (e.g. 'orders' or 'orders-api')."
  }
}

variable "environment" {
  description = "Deployment environment name (e.g. 'dev', 'staging', 'prod'). Production environments ('prod', 'production') automatically receive GZRS redundancy, 30-day soft delete, 90-day version retention, and blob change feed."
  type        = string

  validation {
    condition = contains(
      ["dev", "development", "test", "qa", "uat", "staging", "stage", "preprod", "prod", "production", "sandbox"],
      lower(var.environment)
    )
    error_message = "environment must be one of: dev, development, test, qa, uat, staging, stage, preprod, prod, production, sandbox."
  }
}

variable "app_principal_id" {
  description = "Entra ID Object (Principal) ID of the application's identity (AKS Workload Identity / User-Assigned Managed Identity, App Service Managed Identity, or Service Principal) granted read/write blob access."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.app_principal_id))
    error_message = "app_principal_id must be a valid Entra ID Object ID UUID (e.g. '11111111-2222-3333-4444-555555555555')."
  }
}

# -----------------------------------------------------------------------------
# Placement & Naming Overrides (Optional)
# -----------------------------------------------------------------------------

variable "resource_group_name" {
  description = "Existing Azure Resource Group where the application's storage resources belong. Defaults to '<app_name>-<environment>' (e.g. 'orders-staging', 'orders-prod')."
  type        = string
  default     = null

  validation {
    condition     = var.resource_group_name == null || can(regex("^[\\w._()-]{1,89}[\\w_()-]$|^[\\w_()-]$", var.resource_group_name))
    error_message = "resource_group_name must be a valid Azure Resource Group name (1-90 characters; letters, digits, underscores, parentheses, hyphens, and periods, not ending in a period)."
  }
}

variable "location" {
  description = "Azure region for the storage account (e.g. 'eastus2'). When null (the default), inherited automatically from the application's existing resource group."
  type        = string
  default     = null

  validation {
    condition     = var.location == null || length(trimspace(var.location)) > 0
    error_message = "location, when specified, must be a non-empty Azure region name."
  }
}

variable "storage_account_name_override" {
  description = "Explicit storage account name override (3-24 lowercase letters and numbers). Leave null to let the module deterministically generate a globally unique name."
  type        = string
  default     = null

  validation {
    condition     = var.storage_account_name_override == null || can(regex("^[a-z0-9]{3,24}$", var.storage_account_name_override))
    error_message = "storage_account_name_override must be 3 to 24 characters using only lowercase letters and digits."
  }
}

# -----------------------------------------------------------------------------
# Blob Containers & File Lifecycle
# -----------------------------------------------------------------------------

variable "containers" {
  description = <<-EOT
    Map of private blob containers to create for the application, keyed by container name (e.g. 'uploads', 'media', 'exports').
    Each container supports optional lifecycle overrides:
      - delete_after_days: automatically expire and delete files N days after last modification (ideal for temporary exports and generated reports)
      - cool_after_days:   move unaccessed files to Cool storage after N days
      - cold_after_days:   move unaccessed files to Cold storage after N days
      - metadata:          optional map of lowercase key-value container metadata
  EOT

  type = map(object({
    delete_after_days = optional(number)
    cool_after_days   = optional(number)
    cold_after_days   = optional(number)
    metadata          = optional(map(string), {})
  }))

  default = {
    files = {}
  }

  nullable = false

  validation {
    condition = alltrue([
      for name in keys(var.containers) :
      can(regex("^[a-z0-9]([a-z0-9-]{1,61}[a-z0-9])?$", name)) && !can(regex("--", name))
    ])
    error_message = "Each container name must be 3 to 63 characters, start and end with a lowercase letter or digit, contain only lowercase letters, digits, and hyphens, and have no consecutive hyphens ('--')."
  }

  validation {
    condition = alltrue([
      for c in values(var.containers) :
      c.delete_after_days == null || (c.delete_after_days >= 1 && c.delete_after_days <= 36500 && floor(c.delete_after_days) == c.delete_after_days)
    ])
    error_message = "Container delete_after_days must be a whole number between 1 and 36500."
  }

  validation {
    condition = alltrue([
      for c in values(var.containers) :
      (c.cool_after_days == null || (c.cool_after_days >= 1 && c.cool_after_days <= 36500 && floor(c.cool_after_days) == c.cool_after_days)) &&
      (c.cold_after_days == null || (c.cold_after_days >= 1 && c.cold_after_days <= 36500 && floor(c.cold_after_days) == c.cold_after_days)) &&
      (c.cool_after_days == null || c.cold_after_days == null || c.cold_after_days > c.cool_after_days)
    ])
    error_message = "Container cool_after_days and cold_after_days must be whole numbers between 1 and 36500, and cold_after_days must be greater than cool_after_days when both are set."
  }

  validation {
    condition = alltrue(flatten([
      for c in values(var.containers) : [
        for k in keys(coalesce(c.metadata, {})) : can(regex("^[a-z_][a-z0-9_]*$", k))
      ]
    ]))
    error_message = "Container metadata keys must start with a lowercase ASCII letter or underscore and contain only lowercase ASCII letters, digits, and underscores."
  }
}

# -----------------------------------------------------------------------------
# Additional Entra ID Access & Browser CORS
# -----------------------------------------------------------------------------

variable "enable_user_delegation_sas" {
  description = "Grant 'Storage Blob Delegator' to the application identity (and additional contributors) so the app can sign short-lived User Delegation SAS URLs for browser uploads and downloads without account keys."
  type        = bool
  default     = true
  nullable    = false
}

variable "additional_contributor_principal_ids" {
  description = "Additional Entra ID Principal (Object) IDs that require read/write/delete blob access ('Storage Blob Data Contributor'), such as background workers or staging slot identities."
  type        = set(string)
  default     = []
  nullable    = false

  validation {
    condition = alltrue([
      for id in var.additional_contributor_principal_ids :
      can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", id))
    ])
    error_message = "Every ID in additional_contributor_principal_ids must be a valid Entra ID Object ID UUID."
  }
}

variable "reader_principal_ids" {
  description = "Entra ID Principal (Object) IDs that require read-only blob access ('Storage Blob Data Reader'), such as downstream reporting or consumer services."
  type        = set(string)
  default     = []
  nullable    = false

  validation {
    condition = alltrue([
      for id in var.reader_principal_ids :
      can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", id))
    ])
    error_message = "Every ID in reader_principal_ids must be a valid Entra ID Object ID UUID."
  }
}

variable "cors_rules" {
  description = "Optional CORS rules on the Blob service for direct browser uploads or media playback using User Delegation SAS URLs (maximum 5 rules)."
  type = list(object({
    allowed_origins    = list(string)
    allowed_methods    = optional(list(string), ["GET", "HEAD", "PUT", "OPTIONS"])
    allowed_headers    = optional(list(string), ["x-ms-*", "content-type", "content-length", "if-match", "if-none-match"])
    exposed_headers    = optional(list(string), ["x-ms-*", "etag", "content-length", "content-type"])
    max_age_in_seconds = optional(number, 3600)
  }))
  default  = []
  nullable = false

  validation {
    condition     = length(var.cors_rules) <= 5
    error_message = "Azure Blob Storage supports a maximum of 5 CORS rules."
  }

  validation {
    condition = alltrue([
      for r in var.cors_rules :
      length(r.allowed_origins) > 0 &&
      length(r.allowed_methods) > 0 &&
      alltrue([for m in r.allowed_methods : contains(["DELETE", "GET", "HEAD", "MERGE", "POST", "OPTIONS", "PUT", "PATCH"], upper(m))]) &&
      r.max_age_in_seconds >= 0 && r.max_age_in_seconds <= 2147483647
    ])
    error_message = "Each CORS rule must define non-empty allowed_origins, valid HTTP allowed_methods (DELETE, GET, HEAD, MERGE, POST, OPTIONS, PUT, PATCH), and a non-negative max_age_in_seconds."
  }
}

# -----------------------------------------------------------------------------
# Redundancy, Data Protection & Cost Management Overrides
# -----------------------------------------------------------------------------

variable "replication_type" {
  description = "Storage redundancy override ('LRS', 'ZRS', 'GRS', 'GZRS', 'RAGRS', 'RAGZRS'). Defaults to 'GZRS' for prod/production and 'LRS' for non-production environments."
  type        = string
  default     = null

  validation {
    condition     = var.replication_type == null || contains(["LRS", "ZRS", "GRS", "GZRS", "RAGRS", "RAGZRS"], var.replication_type)
    error_message = "replication_type must be one of: LRS, ZRS, GRS, GZRS, RAGRS, RAGZRS."
  }
}

variable "soft_delete_retention_days" {
  description = "Retention period in days (1-365) for soft-deleted blobs and containers. Defaults to 30 days in prod/production and 7 days in non-production environments."
  type        = number
  default     = null

  validation {
    condition     = var.soft_delete_retention_days == null || (var.soft_delete_retention_days >= 1 && var.soft_delete_retention_days <= 365 && floor(var.soft_delete_retention_days) == var.soft_delete_retention_days)
    error_message = "soft_delete_retention_days must be a whole number between 1 and 365."
  }
}

variable "enable_versioning" {
  description = "Keep previous blob versions automatically when blobs are overwritten or deleted."
  type        = bool
  default     = true
  nullable    = false
}

variable "enable_change_feed" {
  description = "Enable the ordered blob change feed log for auditability. Defaults to true in prod/production and false in non-production environments."
  type        = bool
  default     = null
}

variable "enable_lifecycle_policy" {
  description = "Enable the default storage hygiene lifecycle policy (access-based Cool/Cold tiering and automatic cleanup of old blob versions and snapshots)."
  type        = bool
  default     = true
  nullable    = false
}

variable "default_cool_after_days" {
  description = "Days since a blob was last read before automatically moving it from Hot to Cool tier (with automatic promotion back to Hot if accessed again)."
  type        = number
  default     = 30
  nullable    = false

  validation {
    condition     = var.default_cool_after_days >= 1 && var.default_cool_after_days <= 36500 && floor(var.default_cool_after_days) == var.default_cool_after_days
    error_message = "default_cool_after_days must be a whole number between 1 and 36500."
  }
}

variable "default_cold_after_days" {
  description = "Days since a blob was last read before automatically moving it to online Cold tier (keeps millisecond access latency without offline Archive rehydration delays)."
  type        = number
  default     = 90
  nullable    = false

  validation {
    condition     = var.default_cold_after_days >= 2 && var.default_cold_after_days <= 36500 && floor(var.default_cold_after_days) == var.default_cold_after_days && var.default_cold_after_days > var.default_cool_after_days
    error_message = "default_cold_after_days must be a whole number between 2 and 36500 and strictly greater than default_cool_after_days."
  }
}

variable "noncurrent_version_retention_days" {
  description = "Days to retain noncurrent blob versions and snapshots before automatic cleanup. Defaults to 90 days in prod/production and 30 days in non-production environments."
  type        = number
  default     = null

  validation {
    condition     = var.noncurrent_version_retention_days == null || (var.noncurrent_version_retention_days >= 1 && var.noncurrent_version_retention_days <= 36500 && floor(var.noncurrent_version_retention_days) == var.noncurrent_version_retention_days)
    error_message = "noncurrent_version_retention_days must be a whole number between 1 and 36500."
  }
}

# -----------------------------------------------------------------------------
# Network Security (Service Endpoints, Firewall & Private Link)
# -----------------------------------------------------------------------------

variable "allowed_subnet_ids" {
  description = "Virtual network subnet ARM resource IDs (e.g. AKS node/pod subnets and App Service VNet integration subnets with Microsoft.Storage Service Endpoint) permitted through the storage firewall."
  type        = set(string)
  default     = []
  nullable    = false

  validation {
    condition = alltrue([
      for id in var.allowed_subnet_ids :
      can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.Network/virtualNetworks/[^/]+/subnets/[^/]+$", id))
    ])
    error_message = "Every entry in allowed_subnet_ids must be a valid Azure subnet resource ID."
  }
}

variable "allowed_ip_ranges" {
  description = "Public IPv4 addresses or CIDR ranges (excluding /31 and /32 prefixes per Azure Storage rules) permitted through the storage firewall."
  type        = set(string)
  default     = []
  nullable    = false
}

variable "network_default_action" {
  description = "Default storage firewall action ('Allow' or 'Deny'). Automatically defaults to 'Deny' when allowed_subnet_ids or allowed_ip_ranges are provided, and 'Allow' otherwise."
  type        = string
  default     = null

  validation {
    condition     = var.network_default_action == null || contains(["Allow", "Deny"], var.network_default_action)
    error_message = "network_default_action must be 'Allow' or 'Deny'."
  }
}

variable "public_network_access_enabled" {
  description = "Whether public endpoint network access is enabled on the storage account. Automatically defaults to false when private_endpoint_subnet_id is provided, and true otherwise."
  type        = bool
  default     = null
}

variable "private_endpoint_subnet_id" {
  description = "Optional subnet ARM resource ID in which to create a Blob Private Endpoint (placed in the application's resource group)."
  type        = string
  default     = null

  validation {
    condition = (
      var.private_endpoint_subnet_id == null ||
      can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.Network/virtualNetworks/[^/]+/subnets/[^/]+$", var.private_endpoint_subnet_id))
    )
    error_message = "private_endpoint_subnet_id must be a valid Azure subnet resource ID."
  }
}

variable "private_dns_zone_ids" {
  description = "Optional Private DNS Zone ARM resource IDs (e.g. for 'privatelink.blob.core.windows.net') to link with the Blob Private Endpoint."
  type        = list(string)
  default     = []
  nullable    = false
}

# -----------------------------------------------------------------------------
# Observability, Governance & Tagging
# -----------------------------------------------------------------------------

variable "log_analytics_workspace_id" {
  description = "Optional Azure Monitor Log Analytics Workspace resource ID to receive Blob StorageRead, StorageWrite, StorageDelete logs and Transaction metrics."
  type        = string
  default     = null

  validation {
    condition = (
      var.log_analytics_workspace_id == null ||
      can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.OperationalInsights/workspaces/[^/]+$", var.log_analytics_workspace_id))
    )
    error_message = "log_analytics_workspace_id must be a valid Azure Log Analytics Workspace resource ID."
  }
}

variable "enable_delete_lock" {
  description = "Create an Azure 'CanNotDelete' management lock on the storage account (requires Microsoft.Authorization/locks/write permission on the deployment identity)."
  type        = bool
  default     = false
  nullable    = false
}

variable "tags" {
  description = "Additional tags to merge onto all taggable resources created by the module."
  type        = map(string)
  default     = {}
  nullable    = false
}
