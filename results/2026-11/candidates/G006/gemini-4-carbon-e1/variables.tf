# -----------------------------------------------------------------------------
# Required Inputs — the core facts every application team knows
# -----------------------------------------------------------------------------

variable "app_name" {
  description = "Application identifier (for example, 'orders' or 'checkout-api'). Used for naming and standard resource tags."
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-]{1,62}$", var.app_name)) && length(replace(lower(var.app_name), "/[^a-z0-9]/", "")) >= 2
    error_message = "app_name must be 2-63 characters using letters, numbers, and hyphens, and include at least 2 alphanumeric characters."
  }
}

variable "environment" {
  description = "Deployment environment name (for example, 'dev', 'staging', or 'prod'). Production environments ('prod', 'production', 'prd') automatically receive geo-zone redundancy, longer retention, point-in-time restore, and deletion locks."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{0,31}$", var.environment))
    error_message = "environment must be lowercase alphanumeric characters or hyphens (for example, 'dev', 'staging', or 'prod')."
  }
}

variable "resource_group_name" {
  description = "Name of the application's existing Azure resource group in this environment (for example, 'orders-staging' or 'orders-prod')."
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9._()-]{1,90}$", var.resource_group_name)) && !endswith(var.resource_group_name, ".")
    error_message = "resource_group_name must be a valid Azure resource group name (1-90 characters, cannot end with a period)."
  }
}

variable "location" {
  description = "Azure region of the application's resource group (for example, 'eastus2' or 'westeurope')."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{3,32}$", var.location))
    error_message = "location must be a lowercase Azure region slug without spaces (for example, 'eastus2' or 'westeurope')."
  }
}

variable "app_principal_id" {
  description = "Entra ID Object ID (principal ID) of the application's Managed Identity or AKS Workload Identity. Granted 'Storage Blob Data Contributor' on the storage account."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.app_principal_id))
    error_message = "app_principal_id must be a valid UUID (the Entra ID Object ID of the application identity, not the Client/Application ID)."
  }
}

# -----------------------------------------------------------------------------
# Containers, Lifecycle & Browser Access
# -----------------------------------------------------------------------------

variable "containers" {
  description = <<-EOT
    Map of private Blob Storage containers to provision for the application.
    Keys are container names (for example, 'uploads', 'media', 'exports').
    Each container optionally supports:
      - delete_after_days:    Automatically expire blobs N days after last modification (ideal for temporary reports and exports).
      - cool_after_days:      Override days since last access before moving blobs to Cool storage.
      - cold_after_days:      Override days since last access before moving blobs to Cold storage.
      - metadata:             Key-value metadata pairs on the container (lowercase alphanumeric/underscore keys).
      - reader_principal_ids: Entra ID Object IDs granted read-only access scoped solely to this container.
      - writer_principal_ids: Entra ID Object IDs granted read/write access scoped solely to this container.
  EOT
  type = map(object({
    delete_after_days    = optional(number)
    cool_after_days      = optional(number)
    cold_after_days      = optional(number)
    metadata             = optional(map(string), {})
    reader_principal_ids = optional(set(string), [])
    writer_principal_ids = optional(set(string), [])
  }))
  default = {
    files = {}
  }

  validation {
    condition = alltrue([
      for name, _ in var.containers :
      can(regex("^[a-z0-9]([a-z0-9-]{1,61}[a-z0-9])?$", name)) && !can(regex("--", name))
    ])
    error_message = "Container names must be 3-63 lowercase letters, numbers, and single hyphens, starting and ending with a letter or number."
  }

  validation {
    condition = alltrue([
      for _, cfg in var.containers :
      (cfg.delete_after_days == null || cfg.delete_after_days >= 1) &&
      (cfg.cool_after_days == null || cfg.cool_after_days >= 1) &&
      (cfg.cold_after_days == null || cfg.cold_after_days >= 1) &&
      (cfg.cool_after_days == null || cfg.cold_after_days == null || cfg.cold_after_days > cfg.cool_after_days)
    ])
    error_message = "Container lifecycle thresholds (delete_after_days, cool_after_days, cold_after_days) must be >= 1, and cold_after_days must exceed cool_after_days when both are set."
  }

  validation {
    condition = alltrue(flatten([
      for _, cfg in var.containers : [
        for k, _ in cfg.metadata : can(regex("^[a-z_][a-z0-9_]*$", k))
      ]
    ]))
    error_message = "Container metadata keys must be valid C# identifiers in lowercase (letters, numbers, underscores, not starting with a number)."
  }

  validation {
    condition = alltrue(flatten([
      for _, cfg in var.containers : [
        for pid in setunion(cfg.reader_principal_ids, cfg.writer_principal_ids) :
        can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", pid))
      ]
    ]))
    error_message = "All container reader_principal_ids and writer_principal_ids must be valid Entra ID Object ID UUIDs."
  }
}

variable "cors_rules" {
  description = "Optional CORS rules enabling browsers to upload or fetch blobs directly using short-lived User Delegation SAS URLs."
  type = list(object({
    allowed_origins    = list(string)
    allowed_methods    = optional(list(string), ["GET", "HEAD", "PUT", "OPTIONS"])
    allowed_headers    = optional(list(string), ["x-ms-*", "content-type", "content-length", "if-match", "if-none-match"])
    exposed_headers    = optional(list(string), ["x-ms-*", "etag", "content-length", "content-type"])
    max_age_in_seconds = optional(number, 3600)
  }))
  default = []

  validation {
    condition = length(var.cors_rules) <= 5 && alltrue([
      for rule in var.cors_rules :
      length(rule.allowed_origins) >= 1 &&
      length(rule.allowed_methods) >= 1 &&
      rule.max_age_in_seconds >= 0 &&
      rule.max_age_in_seconds <= 2147483647 &&
      alltrue([
        for m in rule.allowed_methods :
        contains(["DELETE", "GET", "HEAD", "MERGE", "POST", "OPTIONS", "PUT", "PATCH"], m)
      ])
    ])
    error_message = "Azure Blob Storage supports up to 5 CORS rules with non-empty allowed_origins and valid HTTP methods (DELETE, GET, HEAD, MERGE, POST, OPTIONS, PUT, PATCH)."
  }
}

# -----------------------------------------------------------------------------
# Additional Identity & Access Management
# -----------------------------------------------------------------------------

variable "additional_writer_principal_ids" {
  description = "Additional Entra ID Object IDs granted 'Storage Blob Data Contributor' across the entire storage account (for example, a background worker identity)."
  type        = set(string)
  default     = []

  validation {
    condition = alltrue([
      for pid in var.additional_writer_principal_ids :
      can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", pid))
    ])
    error_message = "Every ID in additional_writer_principal_ids must be a valid UUID."
  }
}

variable "reader_principal_ids" {
  description = "Entra ID Object IDs granted read-only 'Storage Blob Data Reader' across the storage account (for example, downstream services or a developer troubleshooting group)."
  type        = set(string)
  default     = []

  validation {
    condition = alltrue([
      for pid in var.reader_principal_ids :
      can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", pid))
    ])
    error_message = "Every ID in reader_principal_ids must be a valid UUID."
  }
}

# -----------------------------------------------------------------------------
# Networking (AKS / App Service VNet Integration & Private Link)
# -----------------------------------------------------------------------------

variable "allowed_subnet_ids" {
  description = "Resource IDs of AKS or App Service VNet subnets (with Microsoft.Storage service endpoint enabled) allowed to reach the storage account. Providing subnets or IP ranges automatically sets the storage firewall default action to Deny."
  type        = set(string)
  default     = []
}

variable "allowed_ip_ranges" {
  description = "Public IPv4 addresses or CIDR blocks (up to /30; /32 suffixes are normalized automatically) allowed through the storage firewall."
  type        = set(string)
  default     = []
}

variable "private_endpoint_subnet_id" {
  description = "Optional subnet ID in which to deploy a Private Endpoint for Blob Storage. When set without allowed_subnet_ids or allowed_ip_ranges, public network access is disabled automatically."
  type        = string
  default     = null
}

variable "private_dns_zone_ids" {
  description = "Optional Private DNS Zone IDs (typically privatelink.blob.core.windows.net) linked to the Private Endpoint."
  type        = list(string)
  default     = []
}

variable "public_network_access_enabled" {
  description = "Explicit override for public_network_access_enabled. Defaults to false when private_endpoint_subnet_id is set without public subnet/IP rules, and true otherwise."
  type        = bool
  default     = null
}

# -----------------------------------------------------------------------------
# Resilience, Retention & Lifecycle Overrides (Environment-Smart Defaults)
# -----------------------------------------------------------------------------

variable "replication_type" {
  description = "Storage replication strategy override (LRS, ZRS, GRS, RAGRS, GZRS, RAGZRS). Defaults to GZRS in production and LRS in non-production."
  type        = string
  default     = null

  validation {
    condition     = var.replication_type == null || contains(["LRS", "ZRS", "GRS", "RAGRS", "GZRS", "RAGZRS"], var.replication_type)
    error_message = "replication_type must be one of LRS, ZRS, GRS, RAGRS, GZRS, or RAGZRS."
  }
}

variable "soft_delete_retention_days" {
  description = "Days to retain soft-deleted blobs, containers, and change feed events (1-365). Defaults to 30 in production and 7 in non-production."
  type        = number
  default     = null

  validation {
    condition     = var.soft_delete_retention_days == null || (var.soft_delete_retention_days >= 1 && var.soft_delete_retention_days <= 365)
    error_message = "soft_delete_retention_days must be between 1 and 365."
  }
}

variable "point_in_time_restore_days" {
  description = "Days of block-blob Point-in-Time Restore history (0 disables PITR; must be strictly less than soft_delete_retention_days). Defaults to 14 in production and 0 in non-production."
  type        = number
  default     = null

  validation {
    condition     = var.point_in_time_restore_days == null || (var.point_in_time_restore_days >= 0 && var.point_in_time_restore_days <= 364)
    error_message = "point_in_time_restore_days must be between 0 and 364."
  }
}

variable "default_cool_after_days" {
  description = "Days since last access before blobs automatically tier from Hot to Cool storage (set null to disable). Access automatically promotes Cool blobs back to Hot."
  type        = number
  default     = 30

  validation {
    condition     = var.default_cool_after_days == null || var.default_cool_after_days >= 1
    error_message = "default_cool_after_days must be >= 1 when set."
  }
}

variable "default_cold_after_days" {
  description = "Days since last access before blobs automatically tier to Cold storage (set null to disable)."
  type        = number
  default     = 90

  validation {
    condition     = var.default_cold_after_days == null || var.default_cold_after_days >= 1
    error_message = "default_cold_after_days must be >= 1 when set."
  }
}

variable "noncurrent_version_retention_days" {
  description = "Days to retain overwritten blob versions and snapshots before automatic deletion. Defaults to 90 in production and 30 in non-production."
  type        = number
  default     = null

  validation {
    condition     = var.noncurrent_version_retention_days == null || var.noncurrent_version_retention_days >= 1
    error_message = "noncurrent_version_retention_days must be >= 1."
  }
}

variable "enable_delete_lock" {
  description = "Whether to protect the storage account with an Azure CanNotDelete management lock. Defaults to true in production and false in non-production."
  type        = bool
  default     = null
}

# -----------------------------------------------------------------------------
# Observability, Naming & Tagging
# -----------------------------------------------------------------------------

variable "log_analytics_workspace_id" {
  description = "Optional Log Analytics Workspace resource ID to receive Blob read/write/delete audit logs and storage capacity/transaction metrics."
  type        = string
  default     = null
}

variable "storage_account_name_override" {
  description = "Optional explicit storage account name (3-24 lowercase letters and numbers). Leave null to auto-generate a globally unique compliant name."
  type        = string
  default     = null

  validation {
    condition     = var.storage_account_name_override == null || can(regex("^[a-z0-9]{3,24}$", var.storage_account_name_override))
    error_message = "storage_account_name_override must be 3-24 lowercase letters and numbers only."
  }
}

variable "tags" {
  description = "Additional Azure tags merged with the module's standard application, environment, and managed_by tags."
  type        = map(string)
  default     = {}
}
