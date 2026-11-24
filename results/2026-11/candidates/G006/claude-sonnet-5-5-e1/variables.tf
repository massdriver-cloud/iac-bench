variable "application" {
  description = "Application name, e.g. \"orders\". Lowercase letters, digits and hyphens. Used for naming and tagging, and to find the resource group (<application>-<environment>) unless resource_group_name is set."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,20}[a-z0-9]$", var.application))
    error_message = "application must be 3-22 characters: lowercase letters, digits and hyphens, starting with a letter and not ending with a hyphen."
  }
}

variable "environment" {
  description = "Environment this storage is for: dev, test, staging or prod. Prod gets geo/zone redundancy and longer data retention."
  type        = string

  validation {
    condition     = contains(["dev", "test", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, test, staging, prod."
  }
}

variable "app_principal_ids" {
  description = "Entra ID object IDs of the application identities (managed identity / workload identity / service principal) that need read-write access to the blobs. Access is via Entra ID only; shared keys are disabled."
  type        = list(string)

  validation {
    condition     = length(var.app_principal_ids) > 0 && alltrue([for id in var.app_principal_ids : can(regex("^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$", id))])
    error_message = "app_principal_ids must contain at least one valid GUID (the object ID, not the client ID)."
  }
}

variable "reader_principal_ids" {
  description = "Optional Entra ID object IDs that only need read access to the blobs (e.g. a reporting identity)."
  type        = list(string)
  default     = []
}

variable "containers" {
  description = "Names of the blob containers to create. All are private."
  type        = list(string)
  default     = ["files"]

  validation {
    condition     = alltrue([for c in var.containers : can(regex("^[a-z0-9]([a-z0-9]|-[a-z0-9])*$", c)) && length(c) >= 3 && length(c) <= 63])
    error_message = "Container names must be 3-63 characters of lowercase letters, digits and single hyphens."
  }
}

variable "resource_group_name" {
  description = "Existing resource group to deploy into. Defaults to \"<application>-<environment>\"."
  type        = string
  default     = null
}

variable "replication_type" {
  description = "Override the replication type (LRS, ZRS, GRS, GZRS, RAGRS, RAGZRS). Default: GZRS for prod, LRS otherwise."
  type        = string
  default     = null

  validation {
    condition     = var.replication_type == null || contains(["LRS", "ZRS", "GRS", "GZRS", "RAGRS", "RAGZRS"], coalesce(var.replication_type, "LRS"))
    error_message = "replication_type must be one of LRS, ZRS, GRS, GZRS, RAGRS, RAGZRS."
  }
}

variable "allowed_subnet_ids" {
  description = "Optional subnet IDs (e.g. AKS / App Service integration subnets) allowed to reach the account. When this or allowed_ip_ranges is set, all other network access is denied."
  type        = list(string)
  default     = []
}

variable "allowed_ip_ranges" {
  description = "Optional public IPs / CIDRs allowed to reach the account (e.g. App Service outbound IPs). Same deny-by-default behaviour as allowed_subnet_ids."
  type        = list(string)
  default     = []
}

variable "blob_retention_days" {
  description = "Days deleted blobs/containers and old blob versions are kept for recovery. Default: 30 for prod, 7 otherwise."
  type        = number
  default     = null

  validation {
    condition     = var.blob_retention_days == null || (coalesce(var.blob_retention_days, 7) >= 1 && coalesce(var.blob_retention_days, 7) <= 365)
    error_message = "blob_retention_days must be between 1 and 365."
  }
}

variable "tags" {
  description = "Extra tags merged onto the standard tags."
  type        = map(string)
  default     = {}
}
