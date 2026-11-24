variable "application_name" {
  description = "Short name of the application, e.g. \"orders\". Must match the application's resource group prefix (the resource group is \"<application_name>-<environment>\")."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,23}$", var.application_name))
    error_message = "application_name must be 2-24 characters: lowercase letters, digits and hyphens, starting with a letter."
  }
}

variable "environment" {
  description = "Environment this storage is for. Production gets geo-redundant storage and longer data-recovery windows."
  type        = string

  validation {
    condition     = contains(["dev", "test", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, test, staging, prod."
  }
}

variable "app_principal_id" {
  description = "Object (principal) ID of the application's Entra ID identity (managed identity or service principal). It is granted read/write/delete access to the blobs in this account."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$", var.app_principal_id))
    error_message = "app_principal_id must be a GUID."
  }
}

variable "containers" {
  description = "Names of the private blob containers to create, e.g. [\"uploads\", \"images\", \"reports\"]. Containers are never publicly accessible."
  type        = set(string)
  default     = ["files"]

  validation {
    condition     = alltrue([for c in var.containers : can(regex("^[a-z0-9](?:[a-z0-9]|-[a-z0-9]){2,62}$", c))])
    error_message = "Container names must be 3-63 characters: lowercase letters, digits and single hyphens, starting and ending with a letter or digit."
  }
}

variable "reader_principal_ids" {
  description = "Optional extra identities that need read-only access (e.g. a reporting job), as a map of a short label to principal object ID."
  type        = map(string)
  default     = {}
}

variable "allowed_subnet_ids" {
  description = "Optional subnet IDs (e.g. the AKS node subnet or App Service integration subnet) allowed to reach the account. If this or allowed_ip_ranges is set, all other network access is denied. Subnets need the Microsoft.Storage service endpoint."
  type        = list(string)
  default     = []
}

variable "allowed_ip_ranges" {
  description = "Optional public IPs or CIDR ranges allowed to reach the account. If this or allowed_subnet_ids is set, all other network access is denied."
  type        = list(string)
  default     = []
}

variable "resource_group_name" {
  description = "Override for the application's resource group. Defaults to \"<application_name>-<environment>\"."
  type        = string
  default     = null
}

variable "replication_type" {
  description = "Override for the replication type (LRS, ZRS, GRS, GZRS). Defaults to GRS in prod and LRS elsewhere."
  type        = string
  default     = null

  validation {
    condition     = var.replication_type == null ? true : contains(["LRS", "ZRS", "GRS", "GZRS"], coalesce(var.replication_type, "LRS"))
    error_message = "replication_type must be one of LRS, ZRS, GRS, GZRS."
  }
}

variable "tags" {
  description = "Extra tags to apply (merged with the standard application/environment tags)."
  type        = map(string)
  default     = {}
}
