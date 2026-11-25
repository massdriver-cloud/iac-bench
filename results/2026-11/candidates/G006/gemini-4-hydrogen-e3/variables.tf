variable "application_name" {
  description = "Short name of the application (lowercase letters, numbers, and hyphens). Used for resource naming and tagging."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,19}$", var.application_name))
    error_message = "application_name must be 2-20 characters, start with a lowercase letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "environment" {
  description = "Deployment environment for the application (e.g., dev, test, staging, prod). Controls defaults such as replication and retention."
  type        = string

  validation {
    condition     = contains(["dev", "test", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, test, staging, prod."
  }
}

variable "resource_group_name" {
  description = "Name of the existing Azure resource group belonging to the application in this environment (e.g., orders-staging)."
  type        = string

  validation {
    condition     = length(trimspace(var.resource_group_name)) > 0
    error_message = "resource_group_name must not be empty."
  }
}

variable "app_identity_principal_id" {
  description = "Entra ID object ID (principal ID) of the application's identity (Managed Identity / Workload Identity / Service Principal). Granted Storage Blob Data Contributor."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.app_identity_principal_id))
    error_message = "app_identity_principal_id must be a valid UUID."
  }
}

variable "location" {
  description = "Azure region where the storage account will be created. Defaults to the platform standard region."
  type        = string
  default     = "eastus2"
}

variable "containers" {
  description = <<-EOT
    Map of private blob containers to create for the application, with optional lifecycle rules.
    Example:
      {
        uploads = {}
        media   = { cool_after_days = 90 }
        reports = { cool_after_days = 30, expire_after_days = 365 }
      }
  EOT
  type = map(object({
    cool_after_days   = optional(number)
    expire_after_days = optional(number)
  }))
  default = {
    files = {}
  }

  validation {
    condition = alltrue([
      for name, _ in var.containers :
      can(regex("^[a-z0-9](?:[a-z0-9-]{1,61}[a-z0-9])$", name)) && !strcontains(name, "--")
    ])
    error_message = "Container names must be 3-63 characters, contain only lowercase letters, numbers, and single hyphens, and start/end with a letter or number."
  }

  validation {
    condition = alltrue([
      for _, cfg in var.containers :
      (cfg.cool_after_days == null || cfg.cool_after_days >= 1) &&
      (cfg.expire_after_days == null || cfg.expire_after_days >= 1) &&
      (cfg.cool_after_days == null || cfg.expire_after_days == null || cfg.expire_after_days > cfg.cool_after_days)
    ])
    error_message = "cool_after_days and expire_after_days must be >= 1, and expire_after_days must be greater than cool_after_days when both are set."
  }
}

variable "replication_type" {
  description = "Optional override for storage account replication (LRS, ZRS, GRS, RAGRS). Defaults to GRS for prod and LRS for non-prod."
  type        = string
  default     = null

  validation {
    condition     = var.replication_type == null || contains(["LRS", "ZRS", "GRS", "RAGRS"], coalesce(var.replication_type, "LRS"))
    error_message = "replication_type must be one of: LRS, ZRS, GRS, RAGRS."
  }
}

variable "access_tier" {
  description = "Default storage access tier for blobs (Hot or Cool). Hot is recommended for active uploads, media, and reports."
  type        = string
  default     = "Hot"

  validation {
    condition     = contains(["Hot", "Cool"], var.access_tier)
    error_message = "access_tier must be Hot or Cool."
  }
}

variable "soft_delete_retention_days" {
  description = "Optional override for blob and container soft-delete retention in days (1-365). Defaults to 30 in prod and 7 in non-prod."
  type        = number
  default     = null

  validation {
    condition     = var.soft_delete_retention_days == null || (coalesce(var.soft_delete_retention_days, 7) >= 1 && coalesce(var.soft_delete_retention_days, 7) <= 365)
    error_message = "soft_delete_retention_days must be between 1 and 365."
  }
}

variable "versioning_enabled" {
  description = "Optional override to enable or disable blob versioning. Enabled by default to protect against accidental overwrites."
  type        = bool
  default     = true
}

variable "noncurrent_version_retention_days" {
  description = "Number of days to retain previous blob versions before automatic lifecycle cleanup."
  type        = number
  default     = 30

  validation {
    condition     = var.noncurrent_version_retention_days >= 1 && var.noncurrent_version_retention_days <= 3650
    error_message = "noncurrent_version_retention_days must be between 1 and 3650."
  }
}

variable "allowed_subnet_ids" {
  description = "Optional list of VNet subnet IDs (e.g., AKS or App Service VNet integration subnets) allowed access. Setting this enables the storage firewall (default deny)."
  type        = list(string)
  default     = []
}

variable "allowed_ip_ranges" {
  description = "Optional list of IPv4 addresses or CIDR blocks allowed through the storage firewall. Setting this enables the storage firewall (default deny)."
  type        = list(string)
  default     = []
}

variable "private_endpoint_subnet_id" {
  description = "Optional subnet ID in which to provision a Private Endpoint for blob access. When set, public network access is disabled."
  type        = string
  default     = null
}

variable "private_dns_zone_ids" {
  description = "Optional list of Private DNS Zone IDs (privatelink.blob.core.windows.net) to attach to the Private Endpoint."
  type        = list(string)
  default     = []
}

variable "cors_allowed_origins" {
  description = "Optional list of browser origins (e.g., https://app.example.com) permitted to access blobs via CORS."
  type        = list(string)
  default     = []
}

variable "additional_contributor_principal_ids" {
  description = "Optional list of additional Entra ID principal IDs granted Storage Blob Data Contributor."
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for id in var.additional_contributor_principal_ids :
      can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", id))
    ])
    error_message = "All entries in additional_contributor_principal_ids must be valid UUIDs."
  }
}

variable "reader_principal_ids" {
  description = "Optional list of Entra ID principal IDs granted Storage Blob Data Reader."
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for id in var.reader_principal_ids :
      can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", id))
    ])
    error_message = "All entries in reader_principal_ids must be valid UUIDs."
  }
}

variable "log_analytics_workspace_id" {
  description = "Optional Log Analytics Workspace resource ID for blob audit logs and transaction metrics."
  type        = string
  default     = null
}

variable "tags" {
  description = "Optional additional tags merged onto all created resources."
  type        = map(string)
  default     = {}
}
