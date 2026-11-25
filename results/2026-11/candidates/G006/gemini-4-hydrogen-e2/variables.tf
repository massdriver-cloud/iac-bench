variable "application_name" {
  type        = string
  description = "Short name of the application (e.g., \"orders\"). Lowercase letters, numbers, and hyphens only."

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{0,30}[a-z0-9])?$", var.application_name)) && length(var.application_name) >= 2
    error_message = "application_name must be 2-32 characters of lowercase letters, numbers, and hyphens, starting and ending with an alphanumeric character."
  }
}

variable "environment" {
  type        = string
  description = "Target deployment environment (\"dev\", \"test\", \"staging\", \"uat\", or \"prod\"). Controls redundancy and retention defaults."

  validation {
    condition     = contains(["dev", "test", "staging", "uat", "prod"], var.environment)
    error_message = "environment must be one of: dev, test, staging, uat, prod."
  }
}

variable "resource_group_name" {
  type        = string
  description = "Name of the application's existing Azure resource group (e.g., \"orders-staging\")."

  validation {
    condition     = length(trimspace(var.resource_group_name)) > 0
    error_message = "resource_group_name must not be empty."
  }
}

variable "principal_id" {
  type        = string
  description = "Entra ID object ID (principal ID) of the application's identity (Managed Identity, Workload Identity, or Service Principal) granted Storage Blob Data Contributor access."

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.principal_id))
    error_message = "principal_id must be a valid Entra ID object UUID."
  }
}

variable "location" {
  type        = string
  description = "Azure region for the storage account."
  default     = "eastus2"
}

variable "storage_account_name" {
  type        = string
  description = "Optional explicit storage account name override (3-24 lowercase alphanumeric characters). When omitted, a globally unique name is derived automatically."
  default     = null

  validation {
    condition     = var.storage_account_name == null || can(regex("^[a-z0-9]{3,24}$", var.storage_account_name))
    error_message = "storage_account_name must be 3-24 lowercase alphanumeric characters."
  }
}

variable "containers" {
  type        = set(string)
  description = "Private blob containers to create for the application's files."
  default     = ["uploads", "media", "exports"]

  validation {
    condition = alltrue([
      for c in var.containers :
      can(regex("^[a-z0-9]([a-z0-9-]{1,61}[a-z0-9])?$", c)) && !can(regex("--", c))
    ])
    error_message = "Each container name must be 3-63 characters of lowercase letters, numbers, and single hyphens, starting and ending with a letter or number."
  }
}

variable "contributor_principal_ids" {
  type        = set(string)
  description = "Additional Entra ID object IDs granted Storage Blob Data Contributor access."
  default     = []

  validation {
    condition = alltrue([
      for id in var.contributor_principal_ids :
      can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", id))
    ])
    error_message = "Each ID in contributor_principal_ids must be a valid Entra ID object UUID."
  }
}

variable "reader_principal_ids" {
  type        = set(string)
  description = "Additional Entra ID object IDs granted read-only Storage Blob Data Reader access."
  default     = []

  validation {
    condition = alltrue([
      for id in var.reader_principal_ids :
      can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", id))
    ])
    error_message = "Each ID in reader_principal_ids must be a valid Entra ID object UUID."
  }
}

variable "allowed_subnet_ids" {
  type        = list(string)
  description = "Optional AKS or App Service VNet integration subnet resource IDs allowed to reach the storage account. When set (or when allowed_ip_rules is set), firewall default action becomes Deny."
  default     = []
}

variable "allowed_ip_rules" {
  type        = list(string)
  description = "Optional public IPv4 addresses or CIDR blocks allowed through the storage firewall."
  default     = []
}

variable "public_network_access_enabled" {
  type        = bool
  description = "Whether public network endpoints are enabled on the storage account. Set to false when exclusively using Private Endpoints."
  default     = true
}

variable "cors_allowed_origins" {
  type        = list(string)
  description = "Optional browser origins allowed for direct-to-blob CORS requests (e.g., direct uploads via User Delegation SAS)."
  default     = []
}

variable "replication_type" {
  type        = string
  description = "Optional replication type override (LRS, GRS, RAGRS, ZRS, GZRS, RAGZRS). Defaults to ZRS in prod and LRS in non-prod."
  default     = null

  validation {
    condition     = var.replication_type == null || contains(["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"], coalesce(var.replication_type, "LRS"))
    error_message = "replication_type must be one of: LRS, GRS, RAGRS, ZRS, GZRS, RAGZRS."
  }
}

variable "cool_tier_after_days" {
  type        = number
  description = "Days since last access before blobs automatically move to Cool storage. Set to 0 to disable."
  default     = 30

  validation {
    condition     = var.cool_tier_after_days >= 0 && floor(var.cool_tier_after_days) == var.cool_tier_after_days
    error_message = "cool_tier_after_days must be a non-negative integer."
  }
}

variable "cold_tier_after_days" {
  type        = number
  description = "Days since last access before blobs automatically move to Cold storage. Set to 0 to disable."
  default     = 90

  validation {
    condition     = var.cold_tier_after_days >= 0 && floor(var.cold_tier_after_days) == var.cold_tier_after_days
    error_message = "cold_tier_after_days must be a non-negative integer."
  }
}

variable "tags" {
  type        = map(string)
  description = "Additional Azure resource tags merged with standard application/environment tags."
  default     = {}
}
