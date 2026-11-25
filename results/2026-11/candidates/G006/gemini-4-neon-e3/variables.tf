# ------------------------------------------------------------------------------
# Required Inputs
# Only the essential, application-level details every app team already knows.
# ------------------------------------------------------------------------------

variable "application_name" {
  type        = string
  description = "Short name of the application owning this storage account (e.g. \"orders\"). Used for compliant resource naming and standard tags."

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,29}$", var.application_name)) && length(replace(var.application_name, "-", "")) >= 2
    error_message = "application_name must be 2-30 characters, start with a lowercase letter, contain only lowercase letters, numbers, and hyphens, and include at least 2 alphanumeric characters."
  }
}

variable "environment" {
  type        = string
  description = "Deployment environment (\"dev\", \"test\", \"staging\", or \"prod\"). Automatically configures appropriate redundancy, data protection, and deletion safeguards."

  validation {
    condition     = contains(["dev", "test", "staging", "prod"], var.environment)
    error_message = "environment must be one of: \"dev\", \"test\", \"staging\", \"prod\"."
  }
}

variable "resource_group_name" {
  type        = string
  description = "Name of the application's existing Azure resource group (e.g. \"orders-staging\", \"orders-prod\")."

  validation {
    condition     = can(regex("^[a-zA-Z0-9._()-]{1,90}$", var.resource_group_name)) && !endswith(var.resource_group_name, ".")
    error_message = "resource_group_name must be 1-90 characters, contain only alphanumerics, periods, underscores, hyphens, and parentheses, and not end with a period."
  }
}

variable "location" {
  type        = string
  description = "Azure region where the storage account will be created (e.g. \"eastus2\", \"westeurope\"). Should match the application's resource group and compute region."

  validation {
    condition     = can(regex("^[a-z0-9]+$", var.location)) && length(var.location) >= 3
    error_message = "location must be a valid lowercase Azure region name without spaces (e.g. \"eastus2\", \"westeurope\")."
  }
}

variable "app_principal_id" {
  type        = string
  description = "Microsoft Entra ID object ID (principal ID) of the application's managed identity or workload identity. Automatically granted Storage Blob Data Contributor on this storage account."

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.app_principal_id))
    error_message = "app_principal_id must be a valid Entra ID object ID (UUID format)."
  }
}

variable "containers" {
  type = map(object({
    retention_days = optional(number)
  }))
  description = <<-EOT
    Map of private blob containers to create for the application.
    Each key is the container name (e.g. "uploads", "media", "reports").
    Optionally set retention_days to automatically delete blobs after N days (useful for generated reports and temporary exports).
  EOT

  validation {
    condition     = length(var.containers) > 0
    error_message = "At least one container must be specified in containers."
  }

  validation {
    condition = alltrue([
      for name, _ in var.containers :
      can(regex("^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$", name)) && !strcontains(name, "--")
    ])
    error_message = "Each container name must be 3-63 characters, use only lowercase letters, numbers, and hyphens, start and end with a letter or number, and not contain consecutive hyphens."
  }

  validation {
    condition = alltrue([
      for _, cfg in var.containers :
      cfg.retention_days == null ? true : (cfg.retention_days >= 1 && cfg.retention_days <= 36500 && floor(cfg.retention_days) == cfg.retention_days)
    ])
    error_message = "Container retention_days must be a whole number between 1 and 36500 when specified."
  }
}

# ------------------------------------------------------------------------------
# Optional Inputs — Access & Identity
# ------------------------------------------------------------------------------

variable "additional_contributor_principal_ids" {
  type        = set(string)
  default     = []
  description = "Optional additional Entra ID object IDs (e.g. background workers or migration jobs) to grant Storage Blob Data Contributor."

  validation {
    condition = alltrue([
      for id in var.additional_contributor_principal_ids :
      can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", id))
    ])
    error_message = "All values in additional_contributor_principal_ids must be valid UUIDs."
  }
}

variable "reader_principal_ids" {
  type        = set(string)
  default     = []
  description = "Optional Entra ID object IDs (e.g. analytics pipelines or read-only support groups) to grant Storage Blob Data Reader."

  validation {
    condition = alltrue([
      for id in var.reader_principal_ids :
      can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", id))
    ])
    error_message = "All values in reader_principal_ids must be valid UUIDs."
  }
}

# ------------------------------------------------------------------------------
# Optional Inputs — Networking
# ------------------------------------------------------------------------------

variable "allowed_subnet_ids" {
  type        = set(string)
  default     = []
  description = "Optional Azure VNet subnet resource IDs (with Microsoft.Storage service endpoint enabled, such as AKS or App Service integration subnets) allowed through the storage firewall."

  validation {
    condition = alltrue([
      for id in var.allowed_subnet_ids :
      can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.Network/virtualNetworks/[^/]+/subnets/[^/]+$", id))
    ])
    error_message = "All values in allowed_subnet_ids must be valid Azure subnet resource IDs."
  }
}

variable "allowed_ip_ranges" {
  type        = set(string)
  default     = []
  description = "Optional public IPv4 addresses or CIDR ranges (/0 to /30; single IPs without /32) allowed through the storage firewall."

  validation {
    condition = alltrue([
      for ip in var.allowed_ip_ranges :
      can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}(/([0-9]|[12][0-9]|30))?$", ip))
    ])
    error_message = "Each entry in allowed_ip_ranges must be a single IPv4 address (no /32) or an IPv4 CIDR block from /0 to /30."
  }
}

variable "private_endpoint_subnet_id" {
  type        = string
  default     = null
  description = "Optional subnet resource ID in which to deploy a Private Endpoint for the blob service. When set, public network access to the storage account is automatically disabled."

  validation {
    condition     = var.private_endpoint_subnet_id == null ? true : can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.Network/virtualNetworks/[^/]+/subnets/[^/]+$", var.private_endpoint_subnet_id))
    error_message = "private_endpoint_subnet_id must be a valid Azure subnet resource ID."
  }
}

variable "private_dns_zone_id" {
  type        = string
  default     = null
  description = "Optional Azure Private DNS Zone ID for privatelink.blob.core.windows.net. Used only when private_endpoint_subnet_id is set."

  validation {
    condition     = var.private_dns_zone_id == null ? true : can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.Network/privateDnsZones/[^/]+$", var.private_dns_zone_id))
    error_message = "private_dns_zone_id must be a valid Azure Private DNS Zone resource ID."
  }
}

variable "cors_allowed_origins" {
  type        = list(string)
  default     = []
  description = "Optional list of web application origins (e.g. [\"https://orders.example.com\"]) permitted for direct browser uploads/downloads via CORS. Wildcards (\"*\") are not allowed."

  validation {
    condition = alltrue([
      for origin in var.cors_allowed_origins :
      can(regex("^(https://[^*\\s]+|http://localhost(:[0-9]+)?)$", origin))
    ])
    error_message = "Each entry in cors_allowed_origins must be an explicit HTTPS origin (or http://localhost[:port]) with no wildcards."
  }
}

# ------------------------------------------------------------------------------
# Optional Inputs — Reliability, Cost & Lifecycle
# ------------------------------------------------------------------------------

variable "enable_geo_redundancy" {
  type        = bool
  default     = false
  description = "Enable cross-region geo-redundancy for regional disaster recovery. Upgrades prod from ZRS to GZRS and non-prod from LRS to GRS."
}

variable "enable_auto_tiering" {
  type        = bool
  default     = true
  description = "Automatically move untouched blobs from Hot to Cool and Cold tiers based on last access time to reduce storage costs."
}

variable "cool_tier_after_days" {
  type        = number
  default     = 30
  description = "Number of days without access before blobs are automatically moved to the Cool tier (when enable_auto_tiering is true)."

  validation {
    condition     = var.cool_tier_after_days >= 1 && var.cool_tier_after_days <= 3650 && floor(var.cool_tier_after_days) == var.cool_tier_after_days
    error_message = "cool_tier_after_days must be a whole number between 1 and 3650."
  }
}

variable "cold_tier_after_days" {
  type        = number
  default     = 90
  description = "Number of days without access before blobs are automatically moved to the Cold tier (when enable_auto_tiering is true). Must be greater than cool_tier_after_days."

  validation {
    condition     = var.cold_tier_after_days >= 2 && var.cold_tier_after_days <= 3650 && floor(var.cold_tier_after_days) == var.cold_tier_after_days
    error_message = "cold_tier_after_days must be a whole number between 2 and 3650."
  }
}

variable "enable_delete_lock" {
  type        = bool
  default     = null
  description = "Attach an Azure CanNotDelete management lock to prevent accidental deletion. Defaults to true in prod and false in non-prod environments."
}

# ------------------------------------------------------------------------------
# Optional Inputs — Observability & Tagging
# ------------------------------------------------------------------------------

variable "log_analytics_workspace_id" {
  type        = string
  default     = null
  description = "Optional Log Analytics Workspace resource ID for storing blob audit logs (Read/Write/Delete) and storage metrics."

  validation {
    condition     = var.log_analytics_workspace_id == null ? true : can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.OperationalInsights/workspaces/[^/]+$", var.log_analytics_workspace_id))
    error_message = "log_analytics_workspace_id must be a valid Log Analytics Workspace resource ID."
  }
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Additional tags to apply to all taggable resources, merged with standard module tags (application, environment, managed_by)."
}
