# ------------------------------------------------------------------------------
# Required Inputs — the minimum every app team needs to provide
# ------------------------------------------------------------------------------

variable "app_name" {
  description = "Short, lowercase name of the application (e.g., \"orders\", \"media-service\"). Used for naming and tagging."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,38}[a-z0-9]$", var.app_name))
    error_message = "app_name must be 3-40 characters, start and end with a lowercase letter or digit, and contain only lowercase letters, digits, and hyphens."
  }
}

variable "environment" {
  description = "Deployment environment for the application. Drives sensible defaults for redundancy, retention, point-in-time restore, and delete protection."
  type        = string

  validation {
    condition     = contains(["dev", "test", "staging", "prod"], var.environment)
    error_message = "environment must be one of: \"dev\", \"test\", \"staging\", \"prod\"."
  }
}

variable "resource_group_name" {
  description = "Name of the application's existing Azure resource group for this environment (e.g., \"orders-staging\", \"orders-prod\")."
  type        = string

  validation {
    condition     = length(trimspace(var.resource_group_name)) > 0 && length(var.resource_group_name) <= 90
    error_message = "resource_group_name must be a non-empty string of at most 90 characters."
  }
}

variable "location" {
  description = "Azure region where the storage account will be created (e.g., \"eastus2\", \"westeurope\"). Colocate with your AKS cluster or App Service."
  type        = string

  validation {
    condition     = length(trimspace(var.location)) > 0
    error_message = "location must be a non-empty Azure region name (e.g., \"eastus2\")."
  }
}

variable "app_principal_id" {
  description = "Entra ID object ID (principal ID) of the application's managed identity or AKS workload identity. Granted least-privilege Storage Blob Data Contributor access."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.app_principal_id))
    error_message = "app_principal_id must be a valid Entra ID object ID (UUID format)."
  }
}

variable "containers" {
  description = <<-EOT
    Blob containers to create for the application. Keys are container names; all containers are private.
    Each container supports optional lifecycle rules (in days since last modification):
      - cool_after_days:    automatically move blobs to Cool storage after N days
      - archive_after_days: automatically move blobs to Archive storage after N days
      - expire_after_days:  automatically delete blobs after N days (ideal for generated reports/exports)
  EOT
  type = map(object({
    cool_after_days    = optional(number)
    archive_after_days = optional(number)
    expire_after_days  = optional(number)
  }))

  validation {
    condition     = length(var.containers) > 0
    error_message = "At least one container must be defined in containers (e.g., { uploads = {} })."
  }

  validation {
    condition = alltrue([
      for name in keys(var.containers) :
      can(regex("^[a-z0-9]([a-z0-9-]{1,61}[a-z0-9])?$", name)) && !can(regex("--", name))
    ])
    error_message = "Container names must be 3-63 characters, lowercase letters, digits, or single hyphens, and start and end with a letter or digit."
  }

  validation {
    condition = alltrue([
      for c in values(var.containers) : (
        (c.cool_after_days == null || c.cool_after_days >= 1) &&
        (c.archive_after_days == null || c.archive_after_days >= 1) &&
        (c.expire_after_days == null || c.expire_after_days >= 1) &&
        (c.cool_after_days == null || c.archive_after_days == null || c.cool_after_days < c.archive_after_days) &&
        (c.cool_after_days == null || c.expire_after_days == null || c.cool_after_days < c.expire_after_days) &&
        (c.archive_after_days == null || c.expire_after_days == null || c.archive_after_days < c.expire_after_days)
      )
    ])
    error_message = "Lifecycle day thresholds must be >= 1 and strictly ordered: cool_after_days < archive_after_days < expire_after_days."
  }
}

# ------------------------------------------------------------------------------
# Optional Access Control
# ------------------------------------------------------------------------------

variable "additional_contributor_principal_ids" {
  description = "Optional set of additional Entra ID object IDs (e.g., background worker identities) to grant Storage Blob Data Contributor access."
  type        = set(string)
  default     = []

  validation {
    condition = alltrue([
      for id in var.additional_contributor_principal_ids :
      can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", id))
    ])
    error_message = "Every entry in additional_contributor_principal_ids must be a valid UUID."
  }
}

variable "reader_principal_ids" {
  description = "Optional set of Entra ID object IDs (e.g., reporting services or support groups) to grant read-only Storage Blob Data Reader access."
  type        = set(string)
  default     = []

  validation {
    condition = alltrue([
      for id in var.reader_principal_ids :
      can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", id))
    ])
    error_message = "Every entry in reader_principal_ids must be a valid UUID."
  }
}

# ------------------------------------------------------------------------------
# Optional Networking (AKS & App Service connectivity)
# ------------------------------------------------------------------------------

variable "allowed_subnet_ids" {
  description = "List of Azure VNet subnet resource IDs allowed through the storage firewall (e.g., AKS node subnets or App Service VNet-integration subnets with the Microsoft.Storage service endpoint enabled)."
  type        = list(string)
  default     = []
}

variable "allowed_ip_ranges" {
  description = "List of public IPv4 addresses or CIDR blocks (/0 to /30) allowed through the storage firewall (e.g., App Service outbound IPs when not VNet-integrated). Note: Azure does not allow /31 or /32 suffixes; pass single IPs without a mask."
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for ip in var.allowed_ip_ranges :
      !can(regex("/3[12]$", ip))
    ])
    error_message = "Azure Storage firewall ip_rules do not allow /31 or /32 CIDR ranges; pass single IP addresses without a CIDR suffix."
  }
}

variable "private_endpoint" {
  description = <<-EOT
    Optional Private Endpoint configuration for private-only blob access from AKS or VNet-integrated App Service.
    When provided, public network access is automatically disabled unless allow_public_network_access is set to true.
      - subnet_id:            resource ID of the subnet where the Private Endpoint NIC will be placed
      - private_dns_zone_ids: optional list of Private DNS Zone IDs (e.g., privatelink.blob.core.windows.net) for automatic DNS registration
  EOT
  type = object({
    subnet_id            = string
    private_dns_zone_ids = optional(list(string), [])
  })
  default = null
}

variable "allow_public_network_access" {
  description = "Override public_network_access_enabled. Defaults to false when private_endpoint is configured, and true (behind a default-deny firewall) otherwise."
  type        = bool
  default     = null
}

# ------------------------------------------------------------------------------
# Optional Storage, Redundancy & Data Protection Overrides
# ------------------------------------------------------------------------------

variable "storage_account_name_override" {
  description = "Optional explicit storage account name (3-24 lowercase alphanumeric characters, globally unique). Leave null to let the module generate a deterministic compliant name."
  type        = string
  default     = null

  validation {
    condition     = var.storage_account_name_override == null || can(regex("^[a-z0-9]{3,24}$", var.storage_account_name_override))
    error_message = "storage_account_name_override must be 3-24 lowercase letters and digits only."
  }
}

variable "replication_type" {
  description = "Storage replication strategy. Defaults to GRS for prod and LRS for non-prod. Allowed values: LRS, ZRS, GRS, RAGRS, GZRS, RAGZRS."
  type        = string
  default     = null

  validation {
    condition     = var.replication_type == null || contains(["LRS", "ZRS", "GRS", "RAGRS", "GZRS", "RAGZRS"], var.replication_type)
    error_message = "replication_type must be one of: LRS, ZRS, GRS, RAGRS, GZRS, RAGZRS."
  }
}

variable "access_tier" {
  description = "Default blob access tier for the storage account (\"Hot\" for active uploads/media, \"Cool\" for infrequently accessed files)."
  type        = string
  default     = "Hot"

  validation {
    condition     = contains(["Hot", "Cool"], var.access_tier)
    error_message = "access_tier must be either \"Hot\" or \"Cool\"."
  }
}

variable "blob_soft_delete_days" {
  description = "Number of days to retain soft-deleted blobs (1-365). Defaults to 30 in prod and 7 in non-prod."
  type        = number
  default     = null

  validation {
    condition     = var.blob_soft_delete_days == null || (var.blob_soft_delete_days >= 1 && var.blob_soft_delete_days <= 365)
    error_message = "blob_soft_delete_days must be between 1 and 365."
  }
}

variable "container_soft_delete_days" {
  description = "Number of days to retain soft-deleted containers (1-365). Defaults to 30 in prod and 7 in non-prod."
  type        = number
  default     = null

  validation {
    condition     = var.container_soft_delete_days == null || (var.container_soft_delete_days >= 1 && var.container_soft_delete_days <= 365)
    error_message = "container_soft_delete_days must be between 1 and 365."
  }
}

variable "point_in_time_restore_days" {
  description = "Number of days for blob point-in-time restore (0 to disable). Defaults to 14 in prod (capped below blob_soft_delete_days) and 0 in non-prod. Must be strictly less than blob_soft_delete_days when enabled."
  type        = number
  default     = null

  validation {
    condition     = var.point_in_time_restore_days == null || (var.point_in_time_restore_days >= 0 && var.point_in_time_restore_days <= 364)
    error_message = "point_in_time_restore_days must be between 0 and 364."
  }
}

variable "previous_version_retention_days" {
  description = "Number of days to keep non-current blob versions before automatically deleting them via lifecycle policy. Defaults to 90 in prod and 30 in non-prod."
  type        = number
  default     = null

  validation {
    condition     = var.previous_version_retention_days == null || var.previous_version_retention_days >= 1
    error_message = "previous_version_retention_days must be at least 1."
  }
}

variable "enable_delete_lock" {
  description = "Whether to place a CanNotDelete management lock on the storage account. Defaults to true in prod and false in non-prod."
  type        = bool
  default     = null
}

variable "cors_rules" {
  description = "Optional CORS rules for browser-direct uploads or downloads of images, videos, and files using User Delegation SAS URLs."
  type = list(object({
    allowed_origins    = list(string)
    allowed_methods    = list(string)
    allowed_headers    = optional(list(string), ["*"])
    exposed_headers    = optional(list(string), ["*"])
    max_age_in_seconds = optional(number, 3600)
  }))
  default = []
}

# ------------------------------------------------------------------------------
# Optional Observability, Security Scanning & Tagging
# ------------------------------------------------------------------------------

variable "log_analytics_workspace_id" {
  description = "Optional Log Analytics Workspace resource ID. When set, enables Blob Storage audit logs (StorageRead, StorageWrite, StorageDelete) and Transaction metrics."
  type        = string
  default     = null
}

variable "enable_defender_malware_scanning" {
  description = "Whether to enable Microsoft Defender for Storage with on-upload malware scanning and sensitive data discovery (recommended for untrusted user uploads; incurs Defender costs)."
  type        = bool
  default     = false
}

variable "defender_malware_scan_cap_gb_per_month" {
  description = "Monthly cap in GB for Defender for Storage on-upload malware scanning when enable_defender_malware_scanning is true."
  type        = number
  default     = 5000

  validation {
    condition     = var.defender_malware_scan_cap_gb_per_month >= 1
    error_message = "defender_malware_scan_cap_gb_per_month must be at least 1."
  }
}

variable "tags" {
  description = "Additional Azure resource tags to merge with the standard application, environment, and managed_by tags."
  type        = map(string)
  default     = {}
}
