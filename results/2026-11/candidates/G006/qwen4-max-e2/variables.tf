# ---------------------------------------------------------------------------
# Required inputs — the only two things an app developer must supply.
# ---------------------------------------------------------------------------

variable "resource_group_name" {
  description = "Name of the application's existing resource group for this environment (e.g. \"orders-staging\"). The storage account is created here; the group must already exist."
  type        = string

  validation {
    condition     = length(trimspace(var.resource_group_name)) > 0
    error_message = "resource_group_name must not be empty."
  }
}

variable "name" {
  description = "Short application/workload name (e.g. \"orders\"). Used as the prefix of the storage account name; the module sanitizes it and appends a unique suffix so the result is a valid, globally unique Azure storage account name."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9-]{0,17}$", var.name))
    error_message = "name must be 1-18 characters, start with a letter or digit, and contain only letters, digits and hyphens (e.g. \"orders\")."
  }
}

# ---------------------------------------------------------------------------
# Optional inputs — sensible defaults for everything else.
# ---------------------------------------------------------------------------

variable "principal_ids" {
  description = "Object (principal) IDs of the application's existing Entra ID managed identities (AKS workload identity, App Service system/user-assigned identity, etc.). Each is granted 'Storage Blob Data Contributor' on the account, so the app authenticates with Entra ID — no access keys or SAS tokens needed."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for id in var.principal_ids : can(regex("^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$", id))])
    error_message = "Each principal_id must be an Entra ID object ID (GUID), not an application/client ID."
  }
}

variable "containers" {
  description = "Blob containers to create inside the account. All containers are private (Entra ID/RBAC access only)."
  type        = set(string)
  default     = ["data"]

  validation {
    condition = alltrue([
      for c in var.containers :
      can(regex("^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$", c)) && !strcontains(c, "--")
    ])
    error_message = "Container names must be 3-63 characters, lowercase letters/digits/single hyphens, starting and ending with a letter or digit."
  }
}

variable "replication_type" {
  description = "Redundancy for the account. ZRS (zone-redundant) by default so a single datacenter failure doesn't take the app's files down. Use LRS only for cheap, non-critical scratch data."
  type        = string
  default     = "ZRS"

  validation {
    condition     = contains(["LRS", "ZRS", "GRS", "RAGRS", "GZRS", "RAGZRS"], var.replication_type)
    error_message = "replication_type must be one of LRS, ZRS, GRS, RAGRS, GZRS, RAGZRS."
  }
}

variable "virtual_network_subnet_ids" {
  description = "Optional subnet resource IDs (e.g. the AKS or App Service VNet-integration subnet, with the Microsoft.Storage service endpoint enabled) allowed to reach the account. By default only trusted Azure services may connect; add your app's subnets here for direct access."
  type        = list(string)
  default     = []
}

variable "allowed_ip_ranges" {
  description = "Optional public IP addresses/CIDR ranges allowed through the firewall (e.g. an office egress IP for debugging). Keep empty in normal operation."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Additional tags to apply to all resources. The module always adds managed-by and workload tags."
  type        = map(string)
  default     = {}
}
