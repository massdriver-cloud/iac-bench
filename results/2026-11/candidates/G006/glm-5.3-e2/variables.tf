###############################################################################
# Required inputs - the only decisions an application team has to make.
###############################################################################

variable "name" {
  description = <<-EOT
    The name of the application this storage belongs to, for example "orders".

    The module derives the storage account name from it, so nobody has to
    invent a globally-unique one: the account is named
    st<application><hash> (lower-case letters and digits, max 24 characters),
    computed deterministically from the application and resource group names.
  EOT
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9_-]{0,62}$", var.name))
    error_message = "name must start with a letter or digit and contain only letters, digits, hyphens and underscores."
  }
}

variable "resource_group_name" {
  description = <<-EOT
    The resource group this application runs in, for example "orders-staging"
    or "orders-prod". The storage account and every other resource the module
    creates is placed in this resource group.
  EOT
  type        = string
}

###############################################################################
# Optional inputs - each has the platform default. Only change them when the
# README says you have a reason (see "Escape hatches").
###############################################################################

variable "location" {
  description = "Azure region for the storage account. Leave unset to look it up from the resource group."
  type        = string
  default     = null
}

variable "containers" {
  description = <<-EOT
    Blob containers to create, named after what the application stores in
    them ("uploads", "media", "reports", ...). Containers are always private
    and reachable only with Entra ID authorization.
  EOT
  type        = set(string)
  default     = ["uploads"]

  validation {
    condition     = alltrue([for c in var.containers : can(regex("^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$", c))])
    error_message = "Container names must be 3-63 lower-case letters, digits or hyphens, starting and ending with a letter or digit."
  }
}

variable "file_shares" {
  description = <<-EOT
    Azure file shares to create, as a map of share name to quota in GiB, e.g.
    { content = 100 }. Leave empty unless something genuinely needs an SMB
    file share (App Service content mounts, legacy tooling) - blob storage is
    the default answer for application files.
  EOT
  type        = map(number)
  default     = {}

  validation {
    condition     = alltrue([for n in keys(var.file_shares) : can(regex("^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$", n))])
    error_message = "File share names must be 3-63 lower-case letters, digits or hyphens, starting and ending with a letter or digit."
  }

  validation {
    condition     = alltrue([for quota in values(var.file_shares) : quota >= 1 && quota <= 5120])
    error_message = "File share quotas must be between 1 and 5120 GiB."
  }
}

variable "principal_id" {
  description = <<-EOT
    Object ID of the application's Entra ID identity - the AKS workload
    identity / user-assigned managed identity, or the App Service
    system-assigned managed identity. When set, the module grants that
    identity the data-plane roles it needs on the account (blob access, and
    file access when file shares are requested). This is how the application
    authenticates; strongly recommended.
  EOT
  type        = string
  default     = null
}

variable "replication_type" {
  description = <<-EOT
    Replication for the storage account: LRS, ZRS, GRS or GZRS. Leave unset
    and the module chooses: ZRS for production resource groups, LRS
    everywhere else.
  EOT
  type        = string
  default     = null

  validation {
    condition     = var.replication_type == null || contains(["LRS", "ZRS", "GRS", "GZRS"], var.replication_type)
    error_message = "replication_type must be one of LRS, ZRS, GRS or GZRS, or unset to use the module default."
  }
}

variable "allow_shared_key_access" {
  description = <<-EOT
    Allow shared-key (and SAS token) authorization on the account. Disabled
    by default: applications authenticate with Entra ID. Only enable it when
    something must mount an Azure file share using the storage account key
    (the AKS CSI driver or App Service content mounts) - see README.md.
  EOT
  type        = bool
  default     = false
}

variable "public_network_access_enabled" {
  description = <<-EOT
    Whether the account's public endpoint is reachable from the internet.
    Traffic is authenticated with Entra ID either way. Leave unset
    (recommended): enabled unless private_endpoint_subnet_id is configured.
  EOT
  type        = bool
  default     = null
}

variable "allowed_ip_cidrs" {
  description = <<-EOT
    Public IP ranges (CIDR) allowed to reach the account, for example office
    egress ranges. Leave empty for authenticated-only open access. Supplying
    any entry makes the default network action Deny.
  EOT
  type        = list(string)
  default     = []
}

variable "allowed_subnet_ids" {
  description = <<-EOT
    Subnet resource IDs allowed to reach the account through
    Microsoft.Storage service endpoints. Supplying any entry makes the
    default network action Deny.
  EOT
  type        = list(string)
  default     = []
}

variable "private_endpoint_subnet_id" {
  description = <<-EOT
    Subnet resource ID to attach private endpoints to. When set, the module
    creates private endpoints for the blob and file services in that subnet,
    creates the privatelink DNS zones, links them to the subnet's virtual
    network, and disables public network access on the account.
  EOT
  type        = string
  default     = null
}

variable "log_analytics_workspace_id" {
  description = "ID of a Log Analytics workspace that should receive the account's metrics and data-plane audit logs."
  type        = string
  default     = null
}

variable "tags" {
  description = "Extra tags merged onto the created resources. An `application` tag is always applied from `name`."
  type        = map(string)
  default     = {}
}
