# -----------------------------------------------------------------------------
# Required Inputs (the obvious inputs every application team provides)
# -----------------------------------------------------------------------------

variable "app_name" {
  description = "Short name of the application that owns this storage account (for example, 'orders' or 'media-processor'). Used for naming and standard resource tags."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{0,30}[a-z0-9])?$", var.app_name)) && length(replace(var.app_name, "-", "")) >= 2
    error_message = "app_name must be 2 to 32 lowercase characters using letters, numbers, and hyphens, and must contain at least 2 alphanumeric characters."
  }
}

variable "environment" {
  description = "Deployment environment name (for example, 'dev', 'staging', or 'prod'). Production environments ('prod', 'production', 'prd') automatically enable zone-redundant storage and longer retention windows unless overridden."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{0,18}[a-z0-9])?$", var.environment)) && length(replace(var.environment, "-", "")) >= 2
    error_message = "environment must be 2 to 20 lowercase characters using letters, numbers, and hyphens (for example, 'staging' or 'prod')."
  }
}

variable "resource_group_name" {
  description = "Name of the application's existing Azure resource group where the storage account will be created (for example, 'orders-staging' or 'orders-prod')."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[-\\w._()]{1,90}$", var.resource_group_name)) && !endswith(var.resource_group_name, ".")
    error_message = "resource_group_name must be a valid Azure resource group name (1-90 characters, letters, numbers, underscores, parentheses, hyphens, or periods, not ending with a period)."
  }
}

variable "location" {
  description = "Azure region where the storage account will be created (should match the application's resource group, AKS cluster, or App Service region, such as 'eastus2' or 'westeurope')."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-z0-9]{3,32}$", var.location))
    error_message = "location must be an Azure region slug in lowercase without spaces (for example, 'eastus2', 'centralus', or 'westeurope')."
  }
}

variable "principal_id" {
  description = "Entra ID Object ID (UUID) of the application's identity (Managed Identity, AKS Workload Identity, or Service Principal). Granted Storage Blob Data Contributor access."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.principal_id))
    error_message = "principal_id must be a valid Entra ID Object ID (UUID format, e.g. '11111111-2222-3333-4444-555555555555')."
  }
}

# -----------------------------------------------------------------------------
# Optional Inputs: Containers & Lifecycle Management
# -----------------------------------------------------------------------------

variable "containers" {
  description = <<-EOT
    Map of private blob containers to create for the application, keyed by container name.
    Defaults to a single 'files' container. Each container optionally supports automatic
    tiering and expiration rules (ideal for moving older media to Cool/Cold storage or
    expiring generated reports and exports after N days):
      - cool_after_days   : Move blobs to Cool tier N days after last modification
      - cold_after_days   : Move blobs to Cold tier N days after last modification
      - delete_after_days : Automatically delete blobs N days after last modification
      - metadata          : Optional key-value metadata map on the container
  EOT
  type = map(object({
    cool_after_days   = optional(number)
    cold_after_days   = optional(number)
    delete_after_days = optional(number)
    metadata          = optional(map(string), {})
  }))
  default = {
    files = {}
  }
  nullable = false

  validation {
    condition = alltrue([
      for name, _ in var.containers :
      length(name) >= 3 &&
      length(name) <= 63 &&
      can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", name)) &&
      !can(regex("--", name))
    ])
    error_message = "Container names must be 3-63 characters, start and end with a lowercase letter or number, contain only lowercase letters, numbers, and hyphens, and never contain consecutive hyphens ('--')."
  }

  validation {
    condition = alltrue([
      for _, cfg in var.containers :
      (cfg.cool_after_days == null || (cfg.cool_after_days >= 1 && cfg.cool_after_days <= 36500 && floor(cfg.cool_after_days) == cfg.cool_after_days)) &&
      (cfg.cold_after_days == null || (cfg.cold_after_days >= 1 && cfg.cold_after_days <= 36500 && floor(cfg.cold_after_days) == cfg.cold_after_days)) &&
      (cfg.delete_after_days == null || (cfg.delete_after_days >= 1 && cfg.delete_after_days <= 36500 && floor(cfg.delete_after_days) == cfg.delete_after_days))
    ])
    error_message = "Container lifecycle day thresholds (cool_after_days, cold_after_days, delete_after_days) must be whole numbers between 1 and 36500."
  }

  validation {
    condition = alltrue([
      for _, cfg in var.containers :
      (cfg.cool_after_days == null || cfg.cold_after_days == null || cfg.cold_after_days > cfg.cool_after_days) &&
      (cfg.cool_after_days == null || cfg.delete_after_days == null || cfg.delete_after_days > cfg.cool_after_days) &&
      (cfg.cold_after_days == null || cfg.delete_after_days == null || cfg.delete_after_days > cfg.cold_after_days)
    ])
    error_message = "When multiple lifecycle thresholds are set on a container, they must strictly increase: cool_after_days < cold_after_days < delete_after_days."
  }

  validation {
    condition = alltrue(flatten([
      for _, cfg in var.containers : [
        for meta_key, _ in coalesce(cfg.metadata, {}) :
        can(regex("^[a-z_][a-z0-9_]*$", meta_key))
      ]
    ]))
    error_message = "Container metadata keys must start with a lowercase letter or underscore and contain only lowercase letters, numbers, and underscores."
  }
}

# -----------------------------------------------------------------------------
# Optional Inputs: Identity & Access Control
# -----------------------------------------------------------------------------

variable "enable_user_delegation_sas" {
  description = "Grant 'Storage Blob Delegator' to the application identity (and additional contributors) so the app can issue short-lived Entra-backed User Delegation SAS URLs for direct uploads or report downloads without enabling shared account keys."
  type        = bool
  default     = true
  nullable    = false
}

variable "additional_contributor_principal_ids" {
  description = "Optional set of additional Entra ID Object IDs (for example, background worker identities or App Service deployment slot identities) granted Storage Blob Data Contributor access."
  type        = set(string)
  default     = []
  nullable    = false

  validation {
    condition = alltrue([
      for id in var.additional_contributor_principal_ids :
      can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", id))
    ])
    error_message = "Every entry in additional_contributor_principal_ids must be a valid UUID."
  }
}

variable "additional_reader_principal_ids" {
  description = "Optional set of Entra ID Object IDs (for example, downstream analytics services or support groups) granted read-only Storage Blob Data Reader access."
  type        = set(string)
  default     = []
  nullable    = false

  validation {
    condition = alltrue([
      for id in var.additional_reader_principal_ids :
      can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", id))
    ])
    error_message = "Every entry in additional_reader_principal_ids must be a valid UUID."
  }
}

# -----------------------------------------------------------------------------
# Optional Inputs: Redundancy, Retention & Data Protection
# -----------------------------------------------------------------------------

variable "replication_type" {
  description = "Storage replication strategy ('LRS', 'ZRS', 'GRS', 'GZRS', 'RAGRS', 'RAGZRS'). When null, defaults to 'ZRS' in production environments for availability-zone resilience and 'LRS' in non-production environments."
  type        = string
  default     = null

  validation {
    condition     = var.replication_type == null || contains(["LRS", "ZRS", "GRS", "GZRS", "RAGRS", "RAGZRS"], var.replication_type)
    error_message = "replication_type must be one of 'LRS', 'ZRS', 'GRS', 'GZRS', 'RAGRS', 'RAGZRS', or null for environment-aware defaults."
  }
}

variable "access_tier" {
  description = "Default access tier for the storage account ('Hot' for frequently accessed files, 'Cool' for infrequently accessed archives)."
  type        = string
  default     = "Hot"
  nullable    = false

  validation {
    condition     = contains(["Hot", "Cool"], var.access_tier)
    error_message = "access_tier must be either 'Hot' or 'Cool'."
  }
}

variable "versioning_enabled" {
  description = "Keep previous blob versions automatically when files are overwritten, protecting against accidental application overwrites."
  type        = bool
  default     = true
  nullable    = false
}

variable "noncurrent_version_retention_days" {
  description = "Days to retain non-current blob versions and snapshots before automatic cleanup. When null, defaults to 90 days in production and 14 days in non-production. Set to 0 to retain non-current versions indefinitely."
  type        = number
  default     = null

  validation {
    condition     = var.noncurrent_version_retention_days == null || (var.noncurrent_version_retention_days >= 0 && var.noncurrent_version_retention_days <= 36500 && floor(var.noncurrent_version_retention_days) == var.noncurrent_version_retention_days)
    error_message = "noncurrent_version_retention_days must be a whole number between 0 and 36500, or null."
  }
}

variable "soft_delete_retention_days" {
  description = "Days to retain soft-deleted blobs and containers for recovery. When null, defaults to 30 days in production and 7 days in non-production. Set to 0 to disable soft delete."
  type        = number
  default     = null

  validation {
    condition     = var.soft_delete_retention_days == null || (var.soft_delete_retention_days >= 0 && var.soft_delete_retention_days <= 365 && floor(var.soft_delete_retention_days) == var.soft_delete_retention_days)
    error_message = "soft_delete_retention_days must be a whole number between 0 and 365, or null."
  }
}

variable "change_feed_enabled" {
  description = "Enable the Blob service change feed transaction log (only needed if downstream event consumers or point-in-time restore require it)."
  type        = bool
  default     = false
  nullable    = false
}

variable "enable_delete_lock" {
  description = "Place an Azure Management CanNotDelete lock on the storage account to prevent accidental deletion."
  type        = bool
  default     = false
  nullable    = false
}

# -----------------------------------------------------------------------------
# Optional Inputs: Network Security & Private Connectivity (AKS / App Service)
# -----------------------------------------------------------------------------

variable "allowed_subnet_ids" {
  description = "Optional set of VNet subnet resource IDs (such as AKS node/pod subnets and App Service VNet-integrated subnets with Microsoft.Storage service endpoints). Providing subnets automatically sets the storage firewall default action to 'Deny'."
  type        = set(string)
  default     = []
  nullable    = false
}

variable "allowed_ip_ranges" {
  description = "Optional set of public IPv4 addresses or CIDR blocks (prefix <= /30) allowed through the storage firewall (such as NAT gateway egress IPs). Providing IPs automatically sets the storage firewall default action to 'Deny'."
  type        = set(string)
  default     = []
  nullable    = false
}

variable "network_default_action" {
  description = "Override for the storage account firewall default action ('Allow' or 'Deny'). When null, automatically defaults to 'Deny' if allowed_subnet_ids or allowed_ip_ranges are provided, and 'Allow' otherwise."
  type        = string
  default     = null

  validation {
    condition     = var.network_default_action == null || contains(["Allow", "Deny"], var.network_default_action)
    error_message = "network_default_action must be 'Allow', 'Deny', or null."
  }
}

variable "private_endpoint_subnet_id" {
  description = "Optional subnet resource ID in which to provision a Private Endpoint for the Blob service. When set (and no public subnet/IP rules are specified), public network access is disabled automatically unless public_network_access_enabled is explicitly set."
  type        = string
  default     = null
}

variable "private_dns_zone_ids" {
  description = "Optional list of Private DNS Zone resource IDs (for 'privatelink.blob.core.windows.net') to register with the Blob Private Endpoint."
  type        = list(string)
  default     = []
  nullable    = false
}

variable "public_network_access_enabled" {
  description = "Explicitly enable or disable public network access to the storage account. When null, defaults to false if private_endpoint_subnet_id is set without public firewall rules, and true otherwise."
  type        = bool
  default     = null
}

# -----------------------------------------------------------------------------
# Optional Inputs: Browser CORS, Naming, Diagnostics & Tags
# -----------------------------------------------------------------------------

variable "cors_rules" {
  description = "Optional CORS rules on the Blob service for web frontends uploading or rendering media directly via User Delegation SAS URLs."
  type = list(object({
    allowed_origins    = list(string)
    allowed_methods    = optional(list(string), ["GET", "HEAD", "PUT", "OPTIONS"])
    allowed_headers    = optional(list(string), ["*"])
    exposed_headers    = optional(list(string), ["ETag", "x-ms-request-id"])
    max_age_in_seconds = optional(number, 3600)
  }))
  default  = []
  nullable = false

  validation {
    condition = alltrue(flatten([
      for rule in var.cors_rules : [
        for method in rule.allowed_methods :
        contains(["DELETE", "GET", "HEAD", "MERGE", "POST", "OPTIONS", "PUT", "PATCH"], method)
      ]
    ]))
    error_message = "CORS allowed_methods may only include DELETE, GET, HEAD, MERGE, POST, OPTIONS, PUT, or PATCH."
  }
}

variable "storage_account_name_override" {
  description = "Optional explicit globally unique storage account name (3-24 lowercase letters and numbers). Leave null to let the module generate a compliant, collision-free name automatically."
  type        = string
  default     = null

  validation {
    condition     = var.storage_account_name_override == null || can(regex("^[a-z0-9]{3,24}$", var.storage_account_name_override))
    error_message = "storage_account_name_override must be 3 to 24 characters using only lowercase letters and numbers."
  }
}

variable "log_analytics_workspace_id" {
  description = "Optional Log Analytics Workspace resource ID to receive Blob service read/write/delete audit logs and storage metrics."
  type        = string
  default     = null
}

variable "tags" {
  description = "Additional Azure resource tags merged onto standard application and environment tags."
  type        = map(string)
  default     = {}
  nullable    = false
}
