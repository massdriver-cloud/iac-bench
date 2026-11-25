# ---------------------------------------------------------------------------
# The inputs every team fills in
# ---------------------------------------------------------------------------

variable "application" {
  description = "Short name of the application that owns this storage, e.g. \"orders\". Used for naming and tagging."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,29}$", var.application))
    error_message = "application must be 2-30 characters, start with a letter, and contain only lowercase letters, digits and hyphens (for example \"orders\")."
  }
}

variable "environment" {
  description = "Environment this storage belongs to: dev, test, staging or prod. Drives redundancy, retention and delete protection."
  type        = string

  validation {
    condition     = contains(["dev", "test", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, test, staging, prod."
  }
}

variable "location" {
  description = "Azure region of the application's resource group and virtual network, e.g. \"westeurope\"."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]+$", var.location))
    error_message = "location must be the short region name in lowercase without spaces, for example \"westeurope\" or \"eastus2\"."
  }
}

variable "application_principal_id" {
  description = "Object (principal) ID of the application's Entra ID identity (managed identity or service principal). This identity gets read/write access to the files; nothing else does."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.application_principal_id))
    error_message = "application_principal_id must be the object ID (a GUID) of the application's identity, not its name or client ID display name."
  }
}

variable "private_endpoint_subnet_id" {
  description = "Resource ID of the subnet where the storage account's private endpoint is placed. It must be in (or peered with) the virtual network your AKS cluster / App Service uses, and in the same region as `location`. The account is not reachable from the internet."
  type        = string

  validation {
    condition     = can(regex("(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.Network/virtualNetworks/[^/]+/subnets/[^/]+$", var.private_endpoint_subnet_id))
    error_message = "private_endpoint_subnet_id must be a full subnet resource ID: /subscriptions/<id>/resourceGroups/<rg>/providers/Microsoft.Network/virtualNetworks/<vnet>/subnets/<subnet>."
  }
}

# ---------------------------------------------------------------------------
# Optional inputs - the defaults are the standard
# ---------------------------------------------------------------------------

variable "resource_group_name" {
  description = "Name of the application's existing resource group. Defaults to \"<application>-<environment>\", e.g. \"orders-prod\"."
  type        = string
  default     = null
}

variable "containers" {
  description = <<-EOT
    Blob containers to create, keyed by container name. All containers are private.
    Set `delete_after_days` on a container to have files in it removed automatically
    that many days after they were created (useful for exports and temporary reports);
    leave it out to keep files until the application deletes them.

    Example:
      containers = {
        uploads = {}
        exports = { delete_after_days = 30 }
      }
  EOT
  type = map(object({
    delete_after_days = optional(number)
  }))
  default = {
    files = {}
  }

  validation {
    condition = alltrue([
      for name in keys(var.containers) :
      can(regex("^[a-z0-9]([a-z0-9]|-[a-z0-9]){2,62}$", name)) && length(name) <= 63
    ])
    error_message = "Container names must be 3-63 characters of lowercase letters, digits and single hyphens, and must start and end with a letter or digit."
  }

  validation {
    condition = alltrue([
      for c in values(var.containers) :
      c.delete_after_days == null ? true : (c.delete_after_days >= 1 && floor(c.delete_after_days) == c.delete_after_days)
    ])
    error_message = "delete_after_days must be a whole number of days, 1 or more."
  }
}

variable "private_dns_zone_id" {
  description = "Resource ID of the `privatelink.blob.core.windows.net` private DNS zone linked to your virtual network. When set, the private endpoint registers itself there so the normal blob URL resolves to the private address. Leave null only if your platform registers private endpoint DNS records some other way."
  type        = string
  default     = null

  validation {
    condition     = var.private_dns_zone_id == null ? true : can(regex("(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.Network/privateDnsZones/[^/]+$", var.private_dns_zone_id))
    error_message = "private_dns_zone_id must be a full private DNS zone resource ID: /subscriptions/<id>/resourceGroups/<rg>/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net."
  }
}

variable "replication_type" {
  description = "Storage redundancy. Defaults to GZRS (zone-redundant plus a copy in the paired region) for prod and LRS elsewhere. Override only if the region does not support availability zones (use GRS) or the data has other requirements."
  type        = string
  default     = null

  validation {
    condition     = var.replication_type == null ? true : contains(["LRS", "ZRS", "GRS", "RAGRS", "GZRS", "RAGZRS"], var.replication_type)
    error_message = "replication_type must be one of: LRS, ZRS, GRS, RAGRS, GZRS, RAGZRS."
  }
}

variable "delete_lock_enabled" {
  description = "Put a CanNotDelete lock on the storage account. Defaults to true for prod and false elsewhere. While the lock is on, the account, its containers and its role assignments cannot be deleted; set this to false and apply first if you really intend to remove them."
  type        = bool
  default     = null
}

variable "log_analytics_workspace_id" {
  description = "Resource ID of a Log Analytics workspace. When set, every blob read, write and delete is logged there for auditing."
  type        = string
  default     = null

  validation {
    condition     = var.log_analytics_workspace_id == null ? true : can(regex("(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.OperationalInsights/workspaces/[^/]+$", var.log_analytics_workspace_id))
    error_message = "log_analytics_workspace_id must be a full Log Analytics workspace resource ID."
  }
}

variable "storage_account_name" {
  description = "Exact storage account name to use instead of the generated one. Only needed when importing an account that already exists."
  type        = string
  default     = null

  validation {
    condition     = var.storage_account_name == null ? true : can(regex("^[a-z0-9]{3,24}$", var.storage_account_name))
    error_message = "storage_account_name must be 3-24 characters of lowercase letters and digits only."
  }
}

variable "tags" {
  description = "Extra tags to add to every resource. The module always sets application, environment and managed-by."
  type        = map(string)
  default     = {}
}
