#######################################
# Required inputs - the "couple of obvious inputs" an app team fills in.
#######################################

variable "application_name" {
  description = "Short name of the application, e.g. \"orders\". Lowercase letters, digits and hyphens only. Used to build the storage account name and tags."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{0,30}[a-z0-9]$", var.application_name))
    error_message = "application_name must be 2-32 characters of lowercase letters, digits and hyphens, and must start and end with a letter or digit."
  }
}

variable "environment" {
  description = "Environment the storage belongs to, e.g. \"staging\" or \"prod\". Lowercase letters and digits only. \"prod\" gets stronger redundancy and longer retention."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{2,10}$", var.environment))
    error_message = "environment must be 2-10 lowercase letters or digits (for example dev, staging, prod)."
  }
}

variable "resource_group_name" {
  description = "Name of the application's existing resource group for this environment, e.g. \"orders-staging\". The storage account is created inside it."
  type        = string
}

variable "application_principal_id" {
  description = "Object (principal) ID of the application's Entra ID identity (the managed identity used by the AKS workload or App Service). It is granted data access to the storage account - the application authenticates with its identity, never with keys."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.application_principal_id))
    error_message = "application_principal_id must be a GUID (the object ID of the application's identity)."
  }
}

#######################################
# Optional inputs - sensible defaults, override only when needed.
#######################################

variable "location" {
  description = "Azure region for the storage account. Defaults to the organisation's standard region."
  type        = string
  default     = "westeurope"
}

variable "containers" {
  description = "Blob containers to create for the application's files. Defaults to one container for user-supplied files and one for generated files."
  type        = list(string)
  default     = ["uploads", "exports"]

  validation {
    condition = alltrue([
      for c in var.containers :
      can(regex("^[a-z0-9]([a-z0-9-]{1,61}[a-z0-9])?$", c)) && !strcontains(c, "--")
    ])
    error_message = "Container names must be 3-63 characters of lowercase letters, digits and single hyphens, starting and ending with a letter or digit."
  }

  validation {
    condition     = length(var.containers) == length(distinct(var.containers))
    error_message = "Container names must be unique."
  }
}

variable "allowed_subnet_ids" {
  description = "Optional list of subnet IDs (e.g. the AKS node subnet or App Service VNet-integration subnet) that may reach the account. When this or allowed_ip_ranges is set, all other network access is denied (Azure trusted services are still allowed)."
  type        = list(string)
  default     = []
}

variable "allowed_ip_ranges" {
  description = "Optional list of public IPv4 addresses or CIDR ranges that may reach the account. When this or allowed_subnet_ids is set, all other network access is denied (Azure trusted services are still allowed)."
  type        = list(string)
  default     = []
}

variable "replication_type" {
  description = "Override the storage redundancy. Leave null to let the module choose: zone-redundant (ZRS) in prod, locally redundant (LRS) elsewhere."
  type        = string
  default     = null

  validation {
    condition     = var.replication_type == null || contains(["LRS", "ZRS", "GRS", "GZRS", "RAGRS", "RAGZRS"], coalesce(var.replication_type, "LRS"))
    error_message = "replication_type must be one of LRS, ZRS, GRS, GZRS, RAGRS, RAGZRS."
  }
}

variable "tags" {
  description = "Additional tags to apply to the storage account. Merged with the module's standard tags."
  type        = map(string)
  default     = {}
}
