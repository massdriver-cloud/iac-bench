############################################################################
# The three inputs an app team has to fill in.
############################################################################

variable "application_name" {
  description = "Short name of the application this storage belongs to (e.g. \"orders\"). Lowercase letters and digits only; used to build the storage account name and tags."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,15}$", var.application_name))
    error_message = "application_name must be 2-16 characters, lowercase letters and digits only, starting with a letter (e.g. \"orders\")."
  }
}

variable "environment" {
  description = "Environment this storage is for: one of dev, test, staging, prod. Drives the resource group name (\"<application_name>-<environment>\"), the data-protection settings and the replication level."
  type        = string

  validation {
    condition     = contains(["dev", "test", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, test, staging, prod."
  }
}

variable "application_principal_id" {
  description = "Object (principal) ID of the application's Entra ID identity (the managed identity used by the AKS workload / App Service, or the app's service principal). It is granted data access to the storage account - this is how the application authenticates; there are no keys or connection strings."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.application_principal_id))
    error_message = "application_principal_id must be the object ID (a GUID) of the application's Entra ID identity."
  }
}

############################################################################
# Optional inputs. Sensible defaults; override only if you have a reason.
############################################################################

variable "containers" {
  description = "Blob containers to create for the application's files. Names must be 3-63 characters, lowercase letters, digits and hyphens. Defaults to a single \"files\" container."
  type        = list(string)
  default     = ["files"]

  validation {
    condition = alltrue([
      for c in var.containers : can(regex("^[a-z0-9](-?[a-z0-9]){2,62}$", c))
    ])
    error_message = "Container names must be 3-63 characters of lowercase letters, digits and single hyphens, starting and ending with a letter or digit."
  }

  validation {
    condition     = length(var.containers) == length(distinct(var.containers))
    error_message = "Container names must be unique."
  }
}

variable "resource_group_name" {
  description = "Name of the application's existing resource group. Defaults to the \"<application_name>-<environment>\" convention (e.g. \"orders-staging\"); only set this if your resource group does not follow it."
  type        = string
  default     = null
}

variable "application_can_write" {
  description = "Whether the application identity may create, modify and delete blobs (Storage Blob Data Contributor). Set to false for a read-only application (Storage Blob Data Reader)."
  type        = bool
  default     = true
}

variable "allowed_subnet_ids" {
  description = "Optional list of subnet IDs (e.g. the AKS node subnet or App Service VNet-integration subnet) allowed to reach the storage account. When this and allowed_ip_ranges are both empty the account accepts traffic from any network (still authenticated with Entra ID only). When either is set, everything else is blocked. The subnets must have the Microsoft.Storage service endpoint enabled."
  type        = list(string)
  default     = []
}

variable "allowed_ip_ranges" {
  description = "Optional list of public IPv4 addresses or CIDR ranges allowed to reach the storage account (e.g. an office egress IP for developers). See allowed_subnet_ids for how the firewall is derived."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Additional tags to apply to every resource. The module always adds application, environment and managed-by tags."
  type        = map(string)
  default     = {}
}
