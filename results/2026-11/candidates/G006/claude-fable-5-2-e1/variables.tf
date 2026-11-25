###############################################################################
# Required inputs - the "couple of obvious ones"
###############################################################################

variable "resource_group_name" {
  description = "Name of the application's existing resource group for this environment, e.g. \"orders-staging\" or \"orders-prod\". The storage account is created in it (and, unless `location` is set, in its region). The module never creates or changes the resource group."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[-\\w().]{1,90}$", var.resource_group_name)) && !endswith(var.resource_group_name, ".")
    error_message = "resource_group_name must be the name of an existing resource group (1-90 characters: letters, digits, '-', '_', '.', parentheses), for example \"orders-prod\". Pass the name, not the full resource ID."
  }
}

variable "application_principal_id" {
  description = "Object (principal) ID of the application's own identity in Entra ID - the managed identity or service principal the application runs as on AKS / App Service. It is granted read/write access to the blobs in this account. Use the OBJECT ID shown on the identity's (or Enterprise Application's) overview page, not the application/client ID."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$", var.application_principal_id))
    error_message = "application_principal_id must be a GUID such as \"3f2a6c1e-8b4d-4e7a-9c5f-1d2e3a4b5c6d\" (the object ID of the application's identity)."
  }
}

variable "containers" {
  description = <<-EOT
    The blob containers the application needs, keyed by container name. Think of
    a container as a top-level folder, e.g. "uploads", "media", "exports".
    All containers are private; the application reaches them with its identity.

    Per container you may optionally set:
      delete_after_days       - automatically delete files this many days after
                                they were last written. Use it for things that
                                can be regenerated (reports, exports, temp files).
                                Leave it out for anything users gave you.
      move_to_cool_after_days - move files to the cheaper "cool" tier this many
                                days after they were last written. Sensible for
                                large, rarely-read files (e.g. old videos);
                                use 30 or more to avoid early-move charges.

    Example:
      containers = {
        uploads = {}
        exports = { delete_after_days = 30 }
      }
  EOT
  type = map(object({
    delete_after_days       = optional(number)
    move_to_cool_after_days = optional(number)
  }))
  nullable = false

  validation {
    condition     = length(var.containers) > 0
    error_message = "Declare at least one container, e.g. containers = { uploads = {} }."
  }

  validation {
    condition = alltrue([
      for name in keys(var.containers) :
      length(name) >= 3 && length(name) <= 63 && can(regex("^[a-z0-9]+(-[a-z0-9]+)*$", name))
    ])
    error_message = "Container names must be 3-63 characters of lowercase letters, digits and single hyphens, and must start and end with a letter or digit (e.g. \"user-uploads\")."
  }

  validation {
    condition = alltrue([
      for c in values(var.containers) :
      c.delete_after_days == null ? true : (c.delete_after_days >= 1 && c.delete_after_days <= 36500 && floor(c.delete_after_days) == c.delete_after_days)
    ])
    error_message = "delete_after_days must be a whole number of days, 1 or more."
  }

  validation {
    condition = alltrue([
      for c in values(var.containers) :
      c.move_to_cool_after_days == null ? true : (c.move_to_cool_after_days >= 1 && c.move_to_cool_after_days <= 36500 && floor(c.move_to_cool_after_days) == c.move_to_cool_after_days)
    ])
    error_message = "move_to_cool_after_days must be a whole number of days, 1 or more."
  }

  validation {
    condition = alltrue([
      for c in values(var.containers) :
      (c.delete_after_days == null || c.move_to_cool_after_days == null) ? true : c.move_to_cool_after_days < c.delete_after_days
    ])
    error_message = "When a container sets both, move_to_cool_after_days must be smaller than delete_after_days."
  }
}

###############################################################################
# Network access - closed by default, open exactly what the application needs
###############################################################################

variable "allowed_subnet_ids" {
  description = "Resource IDs of the subnets the application runs in (the AKS node subnet, the App Service VNet-integration subnet). These subnets may reach the storage account; they must have the `Microsoft.Storage` service endpoint enabled. Until you set this and/or `private_endpoint_subnet_id`, nothing can read or write the data."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition = alltrue([
      for id in var.allowed_subnet_ids :
      can(regex("(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.Network/virtualNetworks/[^/]+/subnets/[^/]+$", id))
    ])
    error_message = "Each entry must be a full subnet resource ID: /subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.Network/virtualNetworks/<vnet>/subnets/<subnet>."
  }
}

variable "private_endpoint_subnet_id" {
  description = "Resource ID of a subnet in which to create a private endpoint for the blob service. Use this when your platform routes storage traffic over Private Link. Leave null if the application uses `allowed_subnet_ids` instead."
  type        = string
  default     = null

  validation {
    condition     = var.private_endpoint_subnet_id == null || can(regex("(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.Network/virtualNetworks/[^/]+/subnets/[^/]+$", var.private_endpoint_subnet_id))
    error_message = "private_endpoint_subnet_id must be a full subnet resource ID: /subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.Network/virtualNetworks/<vnet>/subnets/<subnet>."
  }
}

variable "private_dns_zone_id" {
  description = "Resource ID of the `privatelink.blob.core.windows.net` private DNS zone in which to register the private endpoint. Only used together with `private_endpoint_subnet_id`. Leave null if DNS records for private endpoints are created centrally (e.g. by Azure Policy)."
  type        = string
  default     = null

  validation {
    condition     = var.private_dns_zone_id == null || can(regex("(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.Network/privateDnsZones/privatelink\\.blob\\.[^/]+$", var.private_dns_zone_id))
    error_message = "private_dns_zone_id must be the resource ID of a privatelink.blob.* private DNS zone."
  }
}

variable "allowed_ip_ranges" {
  description = "Public IPv4 addresses or CIDR ranges (e.g. an office egress range \"203.0.113.0/24\") that may reach the storage account in addition to the subnets above. Private (10.x, 172.16.x, 192.168.x) ranges and /31 or /32 prefixes are not accepted by Azure - write a single address without a prefix."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition = alltrue([
      for r in var.allowed_ip_ranges :
      can(regex("^((25[0-5]|2[0-4][0-9]|1?[0-9]?[0-9])\\.){3}(25[0-5]|2[0-4][0-9]|1?[0-9]?[0-9])(/([0-9]|[12][0-9]|30))?$", r))
    ])
    error_message = "Each entry must be an IPv4 address (\"203.0.113.10\") or a CIDR range with a prefix of /30 or shorter (\"203.0.113.0/24\")."
  }

  validation {
    condition = alltrue([
      for r in var.allowed_ip_ranges :
      !can(regex("^(10\\.|192\\.168\\.|172\\.(1[6-9]|2[0-9]|3[01])\\.|0\\.0\\.0\\.0)", r))
    ])
    error_message = "allowed_ip_ranges only takes public addresses. For private networks use allowed_subnet_ids or private_endpoint_subnet_id; to open the account to every network set allow_public_network_access = true."
  }
}

variable "allow_public_network_access" {
  description = "Set to true ONLY if clients on the internet must talk to the storage account directly, e.g. browsers uploading or downloading with short-lived links your application hands out. The data never becomes anonymous - every request still needs an Entra ID token or a link signed by the application - but the network firewall no longer restricts where requests come from."
  type        = bool
  default     = false
  nullable    = false
}

variable "cors_allowed_origins" {
  description = "Origins of your web front-end (e.g. [\"https://orders.example.com\"]) whose pages may call the blob endpoint directly from the browser. Only needed for direct browser uploads/downloads."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition = alltrue([
      for o in var.cors_allowed_origins : can(regex("^https://[^/*\\s]+$", o))
    ])
    error_message = "Each origin must be an exact https origin without a path or wildcard, e.g. \"https://orders.example.com\"."
  }
}

###############################################################################
# Access for people
###############################################################################

variable "reader_group_object_ids" {
  description = "Object IDs of Entra ID groups (e.g. the application's developers or support team) that get READ-ONLY access to the stored files, for troubleshooting. Access keys are disabled, so this is the only way for people to look at the data."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition = alltrue([
      for id in var.reader_group_object_ids :
      can(regex("^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$", id))
    ])
    error_message = "Each entry must be the object ID (a GUID) of an Entra ID group."
  }
}

###############################################################################
# Things most teams never need to touch
###############################################################################

variable "location" {
  description = "Azure region for the storage account. Leave null to use the region of the resource group, which is what you want unless your resource group lives in a different region from your application."
  type        = string
  default     = null

  validation {
    condition     = var.location == null || can(regex("^[a-z0-9]+$", var.location))
    error_message = "location must be a region name in its short form, e.g. \"westeurope\" or \"eastus2\"."
  }
}

variable "storage_account_name" {
  description = "Override the generated storage account name. Leave null: the module derives a valid, globally unique and stable name from the resource group. Set it only to adopt (import) an account that already exists, or if the application needs a second account in the same resource group."
  type        = string
  default     = null

  validation {
    condition     = var.storage_account_name == null || can(regex("^[a-z0-9]{3,24}$", var.storage_account_name))
    error_message = "Storage account names must be 3-24 characters, lowercase letters and digits only."
  }
}

variable "replication_type" {
  description = <<-EOT
    How many copies Azure keeps of the data, and where.
      GZRS (default) - three availability zones in the region plus a copy in the
                       paired region. Right choice for anything users gave you.
      GRS            - one datacenter plus the paired region. Use in regions
                       without availability zones.
      ZRS            - three availability zones, single region. Use in regions
                       without a paired region, or when data must not leave the region.
      LRS            - one datacenter. Only for data you can afford to lose
                       (throw-away environments).
  EOT
  type        = string
  default     = "GZRS"
  nullable    = false

  validation {
    condition     = contains(["LRS", "ZRS", "GRS", "GZRS"], var.replication_type)
    error_message = "replication_type must be one of \"GZRS\", \"GRS\", \"ZRS\" or \"LRS\"."
  }
}

variable "recovery_window_days" {
  description = "How long deleted or overwritten files, and deleted containers, can still be recovered. Also bounds how far back the whole account can be rolled back (point-in-time restore: one day less than this)."
  type        = number
  default     = 30
  nullable    = false

  validation {
    condition     = var.recovery_window_days >= 7 && var.recovery_window_days <= 365 && floor(var.recovery_window_days) == var.recovery_window_days
    error_message = "recovery_window_days must be a whole number between 7 and 365."
  }
}

variable "previous_version_retention_days" {
  description = "Every overwrite keeps the previous version of a file. Previous versions older than this many days are cleaned up automatically so that storage cost does not grow forever."
  type        = number
  default     = 90
  nullable    = false

  validation {
    condition     = var.previous_version_retention_days >= 1 && var.previous_version_retention_days <= 36500 && floor(var.previous_version_retention_days) == var.previous_version_retention_days
    error_message = "previous_version_retention_days must be a whole number of days, 1 or more."
  }
}

variable "log_analytics_workspace_id" {
  description = "Resource ID of the Log Analytics workspace that should receive the audit trail of writes and deletes on the stored files. Leave null if diagnostic settings are deployed centrally (e.g. by Azure Policy)."
  type        = string
  default     = null

  validation {
    condition     = var.log_analytics_workspace_id == null || can(regex("(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.OperationalInsights/workspaces/[^/]+$", var.log_analytics_workspace_id))
    error_message = "log_analytics_workspace_id must be a full Log Analytics workspace resource ID."
  }
}

variable "delete_lock_enabled" {
  description = "Put a \"cannot delete\" lock on the storage account so it cannot be removed from the portal or CLI by accident. Recommended for production. Off by default because the lock also blocks legitimate changes made through this module - removing a container or changing who has access - until it is switched off again (set false, apply, make the change, set true), and because the pipeline identity needs permission to manage locks. Deleted files, containers and overwritten versions are recoverable either way."
  type        = bool
  default     = false
  nullable    = false
}

variable "tags" {
  description = "Extra tags for the resources. The tags of the resource group are inherited automatically."
  type        = map(string)
  default     = {}
  nullable    = false
}
