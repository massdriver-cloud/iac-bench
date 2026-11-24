variable "application_name" {
  type        = string
  description = "Short lowercase name of the application (letters and digits, starts with a letter, 2-11 chars). Used in the storage account name and to find the application's resource group."

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,10}$", var.application_name))
    error_message = "application_name must be 2-11 characters, lowercase letters and digits, starting with a letter."
  }
}

variable "environment" {
  type        = string
  description = "Environment the storage is for: dev, staging, or prod."

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "app_identity_object_id" {
  type        = string
  description = "Object ID (GUID) of the application's Entra ID identity (managed identity or service principal). It is granted blob data access on this storage account. No keys are issued."

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.app_identity_object_id))
    error_message = "app_identity_object_id must be a GUID (Entra object ID)."
  }
}

variable "allowed_subnet_ids" {
  type        = list(string)
  description = "Resource IDs of the subnets the application runs in (AKS node/pod subnet or App Service regional VNet integration subnet). Storage is reachable only from these subnets, plus optional IP ranges and trusted Azure services."

  validation {
    condition     = length(var.allowed_subnet_ids) > 0
    error_message = "At least one subnet ID is required so the application can reach its storage."
  }
}

variable "allowed_ip_ranges" {
  type        = list(string)
  description = "Optional public IPv4 CIDRs or addresses allowed through the storage firewall (for example, a CI runner or an office egress address). Leave empty unless needed."
  default     = []
}

variable "resource_group_name" {
  type        = string
  description = "Optional override for the application's resource group. Defaults to \"<application_name>-<environment>\", for example orders-prod."
  default     = null
}

variable "additional_containers" {
  type        = list(string)
  description = "Optional extra private blob containers, beyond the standard uploads, media, reports, and exports containers. Lowercase letters, digits, and hyphens, 3-63 chars."
  default     = []

  validation {
    condition = alltrue([
      for c in var.additional_containers : can(regex("^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$", c)) && !can(regex("--", c))
    ])
    error_message = "Container names must be 3-63 chars of lowercase letters, digits, and single hyphens, starting and ending with a letter or digit."
  }
}

variable "tags" {
  type        = map(string)
  description = "Additional tags to apply to all resources. Owner, application, environment, and managed-by tags are added automatically."
  default     = {}
}
