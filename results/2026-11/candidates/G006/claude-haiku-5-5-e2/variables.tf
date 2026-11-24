variable "app_name" {
  description = "Short lowercase name of the application (e.g. \"orders\"). Must match the application's resource group prefix, e.g. orders-staging. Letters and digits only, 2-10 characters, starting with a letter."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,9}$", var.app_name))
    error_message = "app_name must be 2-10 lowercase letters/digits, starting with a letter (no hyphens), e.g. \"orders\"."
  }
}

variable "environment" {
  description = "Environment the storage is for. The application's resource group is expected to be named <app_name>-<environment>."
  type        = string

  validation {
    condition     = contains(["dev", "test", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, test, staging, prod."
  }
}

variable "app_identity_principal_id" {
  description = "Object ID of the application's Entra ID identity (user-assigned managed identity or service principal) that reads and writes blobs. Granted Storage Blob Data Contributor on the account."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.app_identity_principal_id))
    error_message = "app_identity_principal_id must be an Entra ID object ID (GUID)."
  }
}

variable "containers" {
  description = "Blob containers to create. All are private. Defaults cover user uploads, images/videos, and generated reports/exports."
  type        = list(string)
  default     = ["uploads", "media", "exports"]

  validation {
    condition = alltrue([
      for c in var.containers : can(regex("^[a-z0-9](?:[a-z0-9]|-(?:[a-z0-9])){2,62}$", c))
    ])
    error_message = "Each container name must be 3-63 characters, lowercase letters, digits and single hyphens, starting and ending with a letter or digit."
  }

  validation {
    condition     = length(var.containers) == length(distinct(var.containers)) && length(var.containers) <= 20
    error_message = "containers must be unique and contain at most 20 names."
  }
}

variable "allowed_ip_ranges" {
  description = "Optional public IPv4 CIDRs (e.g. office or NAT egress) allowed to reach the account. When empty, the account is reachable from the internet but still requires Entra ID authentication and TLS 1.2+."
  type        = list(string)
  default     = []
}

variable "allowed_subnet_ids" {
  description = "Optional subnet resource IDs (e.g. AKS node subnet or App Service integration subnet) allowed to reach the account. Setting this, or allowed_ip_ranges, switches the firewall to deny-by-default."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Extra tags to apply to all resources. Owner, environment and managed-by tags are added automatically."
  type        = map(string)
  default     = {}
}
