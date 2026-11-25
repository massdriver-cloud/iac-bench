variable "app_name" {
  type        = string
  description = "Application name, e.g. \"orders\". Must match the application's resource group prefix (<app_name>-<environment>). Lowercase letters, digits and hyphens; at most 11 characters once hyphens are removed."

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.app_name)) && length(var.app_name) <= 32
    error_message = "app_name must be 2-32 characters, start with a letter, and contain only lowercase letters, digits and hyphens."
  }

  validation {
    condition     = length(replace(var.app_name, "-", "")) <= 11
    error_message = "app_name must be at most 11 characters once hyphens are removed (storage account names are limited to 24 characters)."
  }
}

variable "environment" {
  type        = string
  description = "Deployment environment. Selects the application's resource group (<app_name>-<environment>) and the environment's redundancy and protection settings."

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "workload" {
  type        = string
  description = "What the storage is for. uploads = user-provided files; media = images and videos; exports = generated reports and exports. Controls the containers created and the tiering and retention rules applied."

  validation {
    condition     = contains(["uploads", "media", "exports"], var.workload)
    error_message = "workload must be one of: uploads, media, exports."
  }
}

variable "app_identity_object_id" {
  type        = string
  description = "Object ID (GUID) of the application's own Entra ID identity (managed identity or service principal). It is granted data access to the storage account; no keys or connection strings are issued."

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.app_identity_object_id))
    error_message = "app_identity_object_id must be a GUID."
  }
}

variable "allowed_subnet_ids" {
  type        = list(string)
  description = "Optional subnet IDs (e.g. AKS node or App Service integration subnets with the Microsoft.Storage service endpoint) allowed to reach the account. The account denies other network access by default."
  default     = []
}

variable "allowed_ip_ranges" {
  type        = list(string)
  description = "Optional public IPv4 addresses or CIDR ranges allowed to reach the account, e.g. a build agent or office range."
  default     = []
}

variable "log_analytics_workspace_id" {
  type        = string
  description = "Optional Log Analytics workspace ID. When set, blob read/write/delete logs and transaction metrics are sent there."
  default     = null
}

variable "tags" {
  type        = map(string)
  description = "Additional tags to apply to all resources. app, environment, workload and managed-by tags are always set by the module."
  default     = {}
}
