###############################################################################
# The inputs every team fills in
###############################################################################

variable "application" {
  description = "Short name of the application that owns this storage, e.g. \"orders\". Used for naming and tagging."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,28}[a-z0-9]$", var.application))
    error_message = "application must be 2-30 characters: lowercase letters, digits and hyphens, starting with a letter and ending with a letter or digit (e.g. \"orders\")."
  }
}

variable "environment" {
  description = "Environment this storage belongs to. One of: dev, test, qa, uat, staging, preprod, prod. \"prod\" switches on geo-redundancy, a longer recovery window and a delete lock."
  type        = string

  validation {
    condition     = contains(["dev", "test", "qa", "uat", "staging", "preprod", "prod"], var.environment)
    error_message = "environment must be one of: dev, test, qa, uat, staging, preprod, prod."
  }
}

variable "application_principal_id" {
  description = "Object (principal) ID of the application's identity in Entra ID - the managed identity or service principal the app runs as on AKS / App Service. This is the *object ID*, not the client/application ID. It is granted read/write access to the blobs in this account."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.application_principal_id))
    error_message = "application_principal_id must be a GUID (the object ID of the application's identity), e.g. \"1b4e28ba-2fa1-11d2-883f-0016d3cca427\"."
  }
}

###############################################################################
# What the application stores
###############################################################################

variable "containers" {
  description = <<-EOT
    Blob containers to create, keyed by container name. Think of a container as a
    top-level folder, one per kind of file. All containers are private.

    Set `delete_after_days` on containers holding files that are only useful for a
    while (generated reports, exports) and they are cleaned up automatically that
    many days after they were created. Leave it out to keep files until the
    application deletes them.

    Example:
      containers = {
        uploads = {}
        exports = { delete_after_days = 30 }
      }
  EOT
  type = map(object({
    delete_after_days = optional(number)
  }))
  default = {}

  validation {
    condition = alltrue([
      for name in keys(var.containers) :
      can(regex("^[a-z0-9]([a-z0-9]|-[a-z0-9]){2,62}$", name)) && length(name) <= 63
    ])
    error_message = "Container names must be 3-63 characters: lowercase letters, digits and single hyphens, starting and ending with a letter or digit."
  }

  validation {
    condition = alltrue([
      for c in values(var.containers) :
      c.delete_after_days == null ? true : (c.delete_after_days >= 1 && floor(c.delete_after_days) == c.delete_after_days)
    ])
    error_message = "delete_after_days must be a whole number of days, 1 or more (or omitted to keep files indefinitely)."
  }
}

variable "cors_allowed_origins" {
  description = "Only needed if browsers upload to or download from storage directly (e.g. with a short-lived upload link your backend hands out). List the web origins of your front end, e.g. [\"https://orders.example.com\"]. This does not grant access to anything; it only lets browsers on those sites make the request."
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for o in var.cors_allowed_origins :
      can(regex("^(https://[^/*\\s]+|http://localhost(:[0-9]+)?)$", o))
    ])
    error_message = "Each origin must look like \"https://app.example.com\" (no path, no wildcard). \"http://localhost[:port]\" is accepted for local development."
  }
}

###############################################################################
# Who and what can reach the storage
###############################################################################

variable "read_only_principal_ids" {
  description = "Extra Entra ID identities (users, groups or apps) that may read - but not change - the blobs, e.g. a support group or a reporting job. Map of a label of your choice to the identity's object ID: { support-team = \"<object id>\" }."
  type        = map(string)
  default     = {}

  validation {
    condition = alltrue([
      for id in values(var.read_only_principal_ids) :
      can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", id))
    ])
    error_message = "Every value in read_only_principal_ids must be a GUID (an Entra ID object ID)."
  }
}

variable "allowed_subnet_ids" {
  description = "Resource IDs of the subnets the application runs in (the AKS node subnet, the App Service VNet-integration subnet). Only traffic from these subnets - and from the private endpoint, if any - can reach the storage. The subnets need the Microsoft.Storage service endpoint enabled. Ask your platform team if unsure."
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for id in var.allowed_subnet_ids :
      can(regex("(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.Network/virtualNetworks/[^/]+/subnets/[^/]+$", id))
    ])
    error_message = "Each entry must be a full subnet resource ID: /subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.Network/virtualNetworks/<vnet>/subnets/<subnet>."
  }
}

variable "private_endpoint_subnet_id" {
  description = "Resource ID of a subnet in which to create a private endpoint for this storage. Use this instead of (or in addition to) allowed_subnet_ids when your platform uses private endpoints. Leave null for no private endpoint."
  type        = string
  default     = null

  validation {
    condition = var.private_endpoint_subnet_id == null ? true : can(regex(
      "(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.Network/virtualNetworks/[^/]+/subnets/[^/]+$",
      var.private_endpoint_subnet_id
    ))
    error_message = "private_endpoint_subnet_id must be a full subnet resource ID: /subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.Network/virtualNetworks/<vnet>/subnets/<subnet>."
  }
}

variable "private_dns_zone_ids" {
  description = "Resource IDs of the privatelink.blob.core.windows.net private DNS zone(s) to register the private endpoint in. Only used together with private_endpoint_subnet_id. Leave empty if DNS records for private endpoints are created centrally (e.g. by Azure Policy)."
  type        = list(string)
  default     = []
}

variable "allowed_ip_ranges" {
  description = "Public IPv4 addresses or CIDR ranges allowed through the storage firewall, e.g. an office egress IP. Meant as an exception - prefer allowed_subnet_ids. Private (RFC 1918) ranges and /31 or /32 prefixes are not accepted by Azure; give a single address without a prefix instead of a /32."
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for r in var.allowed_ip_ranges :
      can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}$", r)) ? can(cidrhost("${r}/32", 0)) : (
        can(cidrhost(r, 0)) && can(regex("/([1-9]|[12][0-9]|30)$", r))
      )
    ])
    error_message = "Each entry must be a public IPv4 address (\"203.0.113.10\") or a CIDR range with a prefix of /30 or shorter (\"203.0.113.0/24\")."
  }

  validation {
    condition = alltrue([
      for r in var.allowed_ip_ranges :
      !can(regex("^(10\\.|192\\.168\\.|172\\.(1[6-9]|2[0-9]|3[01])\\.|127\\.|0\\.)", r))
    ])
    error_message = "allowed_ip_ranges only accepts public addresses. Traffic from inside a virtual network is allowed with allowed_subnet_ids or a private endpoint instead."
  }
}

###############################################################################
# Things the module decides for you (override only with a reason)
###############################################################################

variable "resource_group_name" {
  description = "Name of the application's existing resource group. Defaults to \"<application>-<environment>\" (e.g. orders-staging), which is how application resource groups are named."
  type        = string
  default     = null

  validation {
    condition     = var.resource_group_name == null ? true : can(regex("^[-\\w.()]{1,89}[-\\w()]$", var.resource_group_name))
    error_message = "resource_group_name is not a valid Azure resource group name."
  }
}

variable "location" {
  description = "Azure region for the storage account. Defaults to the region of the application's resource group."
  type        = string
  default     = null
}

variable "storage_account_name" {
  description = "Override the generated storage account name (3-24 lowercase letters and digits, globally unique). Leave null: the module generates a stable, unique name from the application and environment."
  type        = string
  default     = null

  validation {
    condition     = var.storage_account_name == null ? true : can(regex("^[a-z0-9]{3,24}$", var.storage_account_name))
    error_message = "storage_account_name must be 3-24 characters, lowercase letters and digits only."
  }
}

variable "replication_type" {
  description = "How many copies Azure keeps and where: LRS, ZRS, GRS, RAGRS, GZRS or RAGZRS. Defaults to GRS (copies in a second region) for prod and LRS (three copies in one datacenter) everywhere else."
  type        = string
  default     = null

  validation {
    condition     = var.replication_type == null ? true : contains(["LRS", "ZRS", "GRS", "RAGRS", "GZRS", "RAGZRS"], var.replication_type)
    error_message = "replication_type must be one of: LRS, ZRS, GRS, RAGRS, GZRS, RAGZRS."
  }
}

variable "recovery_days" {
  description = "How many days deleted or overwritten files (and deleted containers) stay recoverable. Defaults to 30 for prod and 7 everywhere else. Longer windows cost more because old copies are kept for longer."
  type        = number
  default     = null

  validation {
    condition     = var.recovery_days == null ? true : (var.recovery_days >= 7 && var.recovery_days <= 365 && floor(var.recovery_days) == var.recovery_days)
    error_message = "recovery_days must be a whole number between 7 and 365."
  }
}

variable "cool_after_days_without_access" {
  description = "Files nobody has read or written for this many days are moved to the cheaper \"cool\" tier, and moved back automatically the next time they are accessed. They stay instantly available either way. Set to null to keep everything in the hot tier."
  type        = number
  default     = 90

  validation {
    condition     = var.cool_after_days_without_access == null ? true : (var.cool_after_days_without_access >= 30 && floor(var.cool_after_days_without_access) == var.cool_after_days_without_access)
    error_message = "cool_after_days_without_access must be a whole number of 30 or more (the cool tier bills a minimum of 30 days), or null to disable."
  }
}

variable "delete_lock_enabled" {
  description = "Put a \"cannot delete\" lock on the storage account so it cannot be removed by accident from the portal, CLI or another pipeline. Defaults to true for prod, false elsewhere. While the lock is on, removing a container or a read-only identity through this module is also refused: set this to false, apply, make the change, and switch it back."
  type        = bool
  default     = null
}

variable "log_analytics_workspace_id" {
  description = "Resource ID of a Log Analytics workspace to send the audit trail of blob writes and deletes to. Leave null to skip."
  type        = string
  default     = null

  validation {
    condition = var.log_analytics_workspace_id == null ? true : can(regex(
      "(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.OperationalInsights/workspaces/[^/]+$",
      var.log_analytics_workspace_id
    ))
    error_message = "log_analytics_workspace_id must be a full Log Analytics workspace resource ID."
  }
}

variable "tags" {
  description = "Extra tags to put on the resources, on top of the application / environment tags the module adds."
  type        = map(string)
  default     = {}
}
