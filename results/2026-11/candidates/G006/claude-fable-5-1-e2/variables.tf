########################################
# Required inputs - the "couple of obvious inputs" an app team fills in
########################################

variable "application_name" {
  description = "Short name of the application that owns this storage, e.g. \"orders\". Used to derive the resource group name, the storage account name and tags."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,30}$", var.application_name))
    error_message = "application_name must be 2-31 characters of lowercase letters, digits and hyphens, starting with a letter."
  }
}

variable "environment" {
  description = "Environment this storage belongs to, e.g. \"dev\", \"staging\" or \"prod\". \"prod\"/\"production\" switch on the production-grade defaults (geo-redundancy, longer soft-delete retention)."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,11}$", var.environment))
    error_message = "environment must be 2-12 lowercase alphanumeric characters, starting with a letter."
  }
}

variable "app_identity_principal_id" {
  description = "Object (principal) ID of the application's Entra ID identity (the managed identity used by the AKS workload or the App Service). It is granted data access to the storage account - no keys or connection strings are needed."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$", var.app_identity_principal_id))
    error_message = "app_identity_principal_id must be a GUID (the object ID of the identity)."
  }
}

########################################
# Optional inputs - sensible defaults, only override when you know why
########################################

variable "resource_group_name" {
  description = "Name of the application's existing resource group. Defaults to \"<application_name>-<environment>\" (e.g. orders-prod)."
  type        = string
  default     = null
}

variable "containers" {
  description = "Blob containers to create inside the account. The defaults cover the common cases: user uploads, images/videos, and generated reports/exports. All containers are private; access is through the application's identity."
  type        = list(string)
  default     = ["uploads", "media", "exports"]

  validation {
    condition = alltrue([
      for c in var.containers :
      length(c) >= 3 && length(c) <= 63 && can(regex("^[a-z0-9](-?[a-z0-9])+$", c))
    ])
    error_message = "Container names must be 3-63 characters of lowercase letters, digits and single hyphens, starting and ending with a letter or digit."
  }

  validation {
    condition     = length(var.containers) == length(distinct(var.containers))
    error_message = "Container names must be unique."
  }
}

variable "app_identity_role" {
  description = "Built-in role granted to the application identity on the storage account. The default allows the app to read, write and delete blobs. Use \"Storage Blob Data Reader\" for read-only workloads or \"Storage Blob Data Owner\" if the app must manage POSIX ACLs."
  type        = string
  default     = "Storage Blob Data Contributor"

  validation {
    condition     = contains(["Storage Blob Data Reader", "Storage Blob Data Contributor", "Storage Blob Data Owner"], var.app_identity_role)
    error_message = "app_identity_role must be one of: Storage Blob Data Reader, Storage Blob Data Contributor, Storage Blob Data Owner."
  }
}

variable "replication_type" {
  description = "Override the storage redundancy. By default production uses GRS (geo-redundant) and every other environment uses LRS."
  type        = string
  default     = null

  validation {
    condition     = var.replication_type == null || contains(["LRS", "ZRS", "GRS", "GZRS", "RAGRS", "RAGZRS"], coalesce(var.replication_type, "LRS"))
    error_message = "replication_type must be one of LRS, ZRS, GRS, GZRS, RAGRS, RAGZRS."
  }
}

variable "allowed_subnet_ids" {
  description = "Optional list of subnet IDs (e.g. the AKS node subnet or an App Service VNet-integration subnet) allowed to reach the account. When this or allowed_ip_ranges is non-empty, all other network access is denied. The subnets need the Microsoft.Storage service endpoint."
  type        = list(string)
  default     = []
}

variable "allowed_ip_ranges" {
  description = "Optional list of public IPv4 addresses or CIDR ranges allowed to reach the account (e.g. App Service outbound IPs). When this or allowed_subnet_ids is non-empty, all other network access is denied."
  type        = list(string)
  default     = []
}

variable "cool_tier_after_days" {
  description = "Files not modified for this many days are automatically moved to the cheaper Cool tier. Set to 0 to disable automatic tiering."
  type        = number
  default     = 90

  validation {
    condition     = var.cool_tier_after_days >= 0 && floor(var.cool_tier_after_days) == var.cool_tier_after_days
    error_message = "cool_tier_after_days must be a non-negative whole number."
  }
}

variable "tags" {
  description = "Extra tags to apply to the storage account. The module always adds application, environment and managed-by tags."
  type        = map(string)
  default     = {}
}
