variable "application" {
  description = "Application name, e.g. \"orders\". Lowercase letters, digits and hyphens. Used for naming and tagging; the application's resource group is assumed to be <application>-<environment> unless resource_group_name is set."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,28}[a-z0-9]$", var.application))
    error_message = "application must be 3-30 characters: lowercase letters, digits and hyphens, starting with a letter and not ending with a hyphen."
  }
}

variable "environment" {
  description = "Environment the storage is for. One of: dev, test, staging, prod. Production gets stronger redundancy, longer data-recovery windows and a delete lock."
  type        = string

  validation {
    condition     = contains(["dev", "test", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, test, staging, prod."
  }
}

variable "app_principal_ids" {
  description = "Entra ID object (principal) IDs of the application's identities that need to read and write blobs, keyed by a short static label (e.g. { aks = \"<object id>\", appservice = \"<object id>\" }). They get 'Storage Blob Data Contributor'. The module disables shared-key access, so access is Entra ID only."
  type        = map(string)

  validation {
    condition     = alltrue([for id in values(var.app_principal_ids) : can(regex("^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$", id))])
    error_message = "Every value in app_principal_ids must be a GUID (the Entra ID object ID of the identity)."
  }
}

variable "containers" {
  description = "Names of blob containers to create (e.g. [\"uploads\", \"images\", \"reports\"]). Containers are always private."
  type        = set(string)
  default     = ["data"]

  validation {
    condition     = alltrue([for c in var.containers : can(regex("^[a-z0-9]([a-z0-9]|-[a-z0-9]){2,62}$", c))])
    error_message = "Container names must be 3-63 characters of lowercase letters, digits and single hyphens, starting and ending with a letter or digit."
  }
}

variable "reader_principal_ids" {
  description = "Optional Entra ID object IDs that only need read access ('Storage Blob Data Reader'), e.g. support or analytics identities."
  type        = map(string)
  default     = {}
}

variable "resource_group_name" {
  description = "Override for the application's existing resource group. Defaults to <application>-<environment>."
  type        = string
  default     = null
}

variable "allowed_subnet_ids" {
  description = "Optional subnet IDs (e.g. the AKS / App Service integration subnets; they need the Microsoft.Storage service endpoint). If this or allowed_ip_ranges is set, all other network access is denied."
  type        = list(string)
  default     = []
}

variable "allowed_ip_ranges" {
  description = "Optional public IPs or CIDR ranges allowed to reach the account. If this or allowed_subnet_ids is set, all other network access is denied."
  type        = list(string)
  default     = []
}

variable "log_analytics_workspace_id" {
  description = "Optional Log Analytics workspace ID. If set, blob read/write/delete audit logs are sent there."
  type        = string
  default     = null
}

variable "tags" {
  description = "Extra tags to apply. Application, environment and managed-by tags are always added."
  type        = map(string)
  default     = {}
}
