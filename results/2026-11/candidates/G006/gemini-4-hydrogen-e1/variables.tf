variable "application_name" {
  description = "Short name of the application (e.g., \"orders\"). Used for resource naming and tagging."
  type        = string

  validation {
    condition     = length(replace(lower(var.application_name), "/[^a-z0-9]/", "")) >= 2 && length(var.application_name) <= 40
    error_message = "application_name must contain at least 2 alphanumeric characters and be at most 40 characters long."
  }
}

variable "environment" {
  description = "Deployment environment (e.g., \"dev\", \"staging\", \"prod\"). Controls replication, versioning, and retention defaults."
  type        = string

  validation {
    condition     = contains(["dev", "development", "test", "qa", "staging", "uat", "sandbox", "prod", "production"], lower(var.environment))
    error_message = "environment must be one of: dev, development, test, qa, staging, uat, sandbox, prod, production."
  }
}

variable "resource_group_name" {
  description = "Name of the existing Azure resource group for this application and environment (e.g., \"orders-staging\")."
  type        = string

  validation {
    condition     = length(trimspace(var.resource_group_name)) > 0
    error_message = "resource_group_name must not be empty."
  }
}

variable "application_principal_id" {
  description = "Entra ID object (principal) ID of the application's identity (Managed Identity, Workload Identity, or Service Principal). Granted Storage Blob Data Contributor on the storage account."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.application_principal_id))
    error_message = "application_principal_id must be a valid UUID (Entra ID object ID)."
  }
}

variable "location" {
  description = "Azure region where the storage account will be created. Should match the application's resource group region."
  type        = string
  default     = "eastus2"
}

variable "storage_account_name_override" {
  description = "Optional explicit storage account name (3-24 lowercase alphanumeric characters). By default, a globally unique name is generated automatically."
  type        = string
  default     = null

  validation {
    condition     = var.storage_account_name_override == null || can(regex("^[a-z0-9]{3,24}$", coalesce(var.storage_account_name_override, "abc")))
    error_message = "storage_account_name_override must be 3-24 lowercase alphanumeric characters."
  }
}

variable "containers" {
  description = "Private blob containers to create, keyed by container name. Optionally specify lifecycle rules (days since last modification) per container."
  type = map(object({
    lifecycle_tier_to_cool_after_days = optional(number, null)
    lifecycle_tier_to_cold_after_days = optional(number, null)
    lifecycle_delete_after_days       = optional(number, null)
  }))
  default = {}

  validation {
    condition = alltrue([
      for name, _ in var.containers :
      can(regex("^[a-z0-9]([a-z0-9-]{1,61}[a-z0-9])?$", name)) && !can(regex("--", name))
    ])
    error_message = "Container names must be 3-63 characters, lowercase letters, numbers, and single hyphens only, starting and ending with a letter or number."
  }

  validation {
    condition = alltrue([
      for _, cfg in var.containers : (
        (cfg.lifecycle_tier_to_cool_after_days == null || cfg.lifecycle_tier_to_cool_after_days >= 1) &&
        (cfg.lifecycle_tier_to_cold_after_days == null || cfg.lifecycle_tier_to_cold_after_days >= 1) &&
        (cfg.lifecycle_delete_after_days == null || cfg.lifecycle_delete_after_days >= 1)
      )
    ])
    error_message = "Lifecycle day thresholds must be >= 1 when specified."
  }

  validation {
    condition = alltrue([
      for _, cfg in var.containers : (
        (cfg.lifecycle_tier_to_cool_after_days == null || cfg.lifecycle_tier_to_cold_after_days == null || cfg.lifecycle_tier_to_cool_after_days < cfg.lifecycle_tier_to_cold_after_days) &&
        (cfg.lifecycle_tier_to_cool_after_days == null || cfg.lifecycle_delete_after_days == null || cfg.lifecycle_tier_to_cool_after_days < cfg.lifecycle_delete_after_days) &&
        (cfg.lifecycle_tier_to_cold_after_days == null || cfg.lifecycle_delete_after_days == null || cfg.lifecycle_tier_to_cold_after_days < cfg.lifecycle_delete_after_days)
      )
    ])
    error_message = "Lifecycle thresholds must satisfy: tier_to_cool_after_days < tier_to_cold_after_days < delete_after_days."
  }
}

variable "additional_role_assignments" {
  description = "Optional map of additional Entra ID identities granted RBAC access to blob data in this storage account."
  type = map(object({
    principal_id         = string
    role_definition_name = optional(string, "Storage Blob Data Reader")
  }))
  default = {}

  validation {
    condition = alltrue([
      for _, cfg in var.additional_role_assignments :
      can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", cfg.principal_id))
    ])
    error_message = "Each principal_id in additional_role_assignments must be a valid UUID."
  }

  validation {
    condition = alltrue([
      for _, cfg in var.additional_role_assignments :
      contains(["Storage Blob Data Reader", "Storage Blob Data Contributor", "Storage Blob Data Owner"], cfg.role_definition_name)
    ])
    error_message = "role_definition_name must be one of: Storage Blob Data Reader, Storage Blob Data Contributor, Storage Blob Data Owner."
  }
}

variable "cors_allowed_origins" {
  description = "Optional list of allowed browser origins for direct-to-blob uploads/downloads (e.g., [\"https://orders.example.com\"])."
  type        = list(string)
  default     = []
}

variable "allowed_subnet_ids" {
  description = "Optional list of VNet subnet IDs (with Microsoft.Storage service endpoint enabled) allowed to access the storage account. When set, public access from other networks is denied."
  type        = list(string)
  default     = []
}

variable "allowed_ip_ranges" {
  description = "Optional list of public IPv4 addresses (without /32) or CIDR ranges (<= /30) allowed through the storage firewall. When set, public access from other networks is denied."
  type        = list(string)
  default     = []
}

variable "private_endpoint_subnet_id" {
  description = "Optional subnet ID in which to create a Private Endpoint for blob storage. When set without allowed_subnet_ids/allowed_ip_ranges, public network access is disabled."
  type        = string
  default     = null
}

variable "private_dns_zone_ids" {
  description = "Optional list of Private DNS Zone IDs (privatelink.blob.core.windows.net) to associate with the Private Endpoint."
  type        = list(string)
  default     = []
}

variable "replication_type_override" {
  description = "Optional override for Azure storage replication type. Defaults to GRS in prod/production and LRS in non-production environments."
  type        = string
  default     = null

  validation {
    condition     = var.replication_type_override == null || contains(["LRS", "ZRS", "GRS", "RAGRS", "GZRS", "RAGZRS"], coalesce(var.replication_type_override, "LRS"))
    error_message = "replication_type_override must be one of: LRS, ZRS, GRS, RAGRS, GZRS, RAGZRS."
  }
}

variable "log_analytics_workspace_id" {
  description = "Optional Log Analytics Workspace resource ID for blob read/write/delete audit logs and transaction metrics."
  type        = string
  default     = null
}

variable "tags" {
  description = "Optional additional tags merged with standard module governance tags."
  type        = map(string)
  default     = {}
}
