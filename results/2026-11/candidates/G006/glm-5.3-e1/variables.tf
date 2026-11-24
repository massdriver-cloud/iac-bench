# =============================================================================
# Required inputs - the handful of obvious things an app team fills in.
# Everything else has a default the platform team stands behind.
# =============================================================================

variable "resource_group_name" {
  description = <<-EOT
    The application's own resource group, e.g. "orders-staging" or
    "orders-prod". The storage account, its containers, the role assignments
    for the application identity and (if used) the private endpoint are all
    created inside this resource group.
  EOT
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9._()-]{1,90}$", var.resource_group_name))
    error_message = "resource_group_name must be 1-90 characters of letters, numbers, '.', '_', '-', '(' and ')'."
  }
}

variable "identity_object_ids" {
  description = <<-EOT
    Object (principal) IDs of the application's Entra ID identities - for
    example the principal_id of the user-assigned managed identity your App
    Service runs under, and/or the principal_id of the AKS workload identity
    your pods use. Each identity is granted "Storage Blob Data Contributor"
    on the storage account, which is the only way applications are expected
    to reach their data (Entra ID / OAuth; account keys are disabled).
  EOT
  type        = list(string)

  validation {
    condition = (
      length(var.identity_object_ids) > 0 &&
      length(distinct(var.identity_object_ids)) == length(var.identity_object_ids) &&
      alltrue([
        for id in var.identity_object_ids :
        can(regex("(?i)^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", id))
      ])
    )
    error_message = "Provide one or more Entra ID object IDs in GUID form (the principal_id of a managed identity or workload identity), without duplicates."
  }
}

variable "containers" {
  description = <<-EOT
    The blob containers the application needs, one object per container:

        containers = [
          { name = "user-uploads" },
          { name = "report-exports", lifecycle = { delete_after_days = 365 } },
        ]

    Attributes:

      name       (required) 3-63 lower-case letters, numbers and hyphens.
      lifecycle  (optional) Overrides the module's default lifecycle rule for
                 this container. See the README for the defaults and for what
                 each lifecycle attribute does.
  EOT
  type = list(object({
    name = string
    lifecycle = optional(object({
      enabled                     = optional(bool, true)
      prefix                      = optional(string)
      cool_after_days             = optional(number)
      archive_after_days          = optional(number)
      delete_after_days           = optional(number)
      delete_versions_after_days  = optional(number)
      delete_snapshots_after_days = optional(number)
    }))
  }))

  validation {
    condition = (
      length(var.containers) > 0 &&
      alltrue([
        for c in var.containers : can(regex("^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$", c.name))
      ]) &&
      length(distinct([for c in var.containers : c.name])) == length(var.containers)
    )
    error_message = "Container names must be 3-63 characters (lower-case letters, numbers and hyphens, starting and ending with a letter or number) and must be unique."
  }
}

# =============================================================================
# Optional inputs - sensible defaults, only touched when there is a reason.
# =============================================================================

variable "location" {
  description = <<-EOT
    (Optional) Azure region for the storage account, e.g. "westeurope".
    Leave unset to use the location of the application's resource group,
    which is almost always what you want.
  EOT
  type        = string
  default     = null
}

variable "account_name_prefix" {
  description = <<-EOT
    (Optional) Prefix for the storage account name instead of the one derived
    from the resource group name. Lower-cased and stripped of anything that is
    not a letter or a digit; a short random suffix is always appended to keep
    the name globally unique, so you never need to invent one yourself.
  EOT
  type        = string
  default     = null
}

variable "replication_type" {
  description = <<-EOT
    Redundancy of the storage account. The module default "ZRS" (zone
    redundant) keeps three copies across availability zones in the region and
    lets the app keep running through a zone outage at a modest premium over
    LRS. Choose "GRS"/"GZRS" (or the read-access "RAGRS"/"RAGZRS") variants if
    a whole-region outage must also be survivable, or "LRS" for throwaway
    data where cost beats resilience. Leave the default unless you know why.
  EOT
  type        = string
  default     = "ZRS"

  validation {
    condition = contains(
      ["LRS", "ZRS", "GRS", "GZRS", "RAGRS", "RAGZRS"],
      var.replication_type
    )
    error_message = "replication_type must be one of LRS, ZRS, GRS, GZRS, RAGRS or RAGZRS."
  }
}

variable "allowed_ip_ranges" {
  description = <<-EOT
    (Optional) Public IP addresses or CIDR ranges (e.g. your office egress)
    that may reach the storage account. Leaving this and allowed_subnet_ids
    empty keeps the account reachable from anywhere over HTTPS - which is
    what AKS and App Service need, since authentication is Entra ID either
    way. Supplying any value switches the default firewall action to Deny,
    so include everything that must reach the account.
  EOT
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for cidr in var.allowed_ip_ranges :
      can(regex("^([0-9]{1,3}[.]){3}[0-9]{1,3}(/[0-9]{1,2})?$", cidr))
    ])
    error_message = "allowed_ip_ranges entries must be an IPv4 address or CIDR range, e.g. \"203.0.113.10\" or \"203.0.113.0/24\"."
  }
}

variable "allowed_subnet_ids" {
  description = <<-EOT
    (Optional) Subnet resource IDs with a "Microsoft.Storage" service endpoint
    that may reach the storage account. Supplying any value (together with
    allowed_ip_ranges, if needed) switches the default firewall action to
    Deny, so include every subnet that must reach the account.
  EOT
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for id in var.allowed_subnet_ids :
      can(regex("^/subscriptions/[0-9a-fA-F-]+/resourceGroups/.+/providers/Microsoft.Network/virtualNetworks/.+/subnets/.+$", id))
    ])
    error_message = "allowed_subnet_ids entries must be full subnet resource IDs."
  }
}

variable "private_endpoint_subnet_id" {
  description = <<-EOT
    (Optional) Subnet resource ID for a private endpoint on the blob service.
    Set this (together with private_dns_zone_id) when your application must
    reach storage over private networking instead of the public endpoint.
    The platform team's private DNS zone for privatelink.blob.core.windows.net
    must already exist; pass its ID via private_dns_zone_id.
  EOT
  type        = string
  default     = null
}

variable "private_dns_zone_id" {
  description = <<-EOT
    (Optional) Resource ID of the existing "privatelink.blob.core.windows.net"
    private DNS zone to link the private endpoint into. Required when
    private_endpoint_subnet_id is set; the module deliberately does not create
    this zone because it is shared platform infrastructure.
  EOT
  type        = string
  default     = null
}

variable "public_network_access_enabled" {
  description = <<-EOT
    (Optional) Whether the storage account is reachable over the public
    endpoint. Defaults to true, which is what AKS and App Service need.
    Set to false only when access happens exclusively through a private
    endpoint (set private_endpoint_subnet_id too).
  EOT
  type        = bool
  default     = true
}

variable "shared_access_key_enabled" {
  description = <<-EOT
    (Optional) Whether account keys (and key-signed SAS) may be used at all.
    Defaults to false: applications authenticate with their Entra ID identity
    and keys are a standing credential nobody needs. Only enable this if a
    legacy tool that cannot speak OAuth has to reach the account, and plan to
    migrate it.
  EOT
  type        = bool
  default     = false
}

variable "subscription_id" {
  description = <<-EOT
    (Optional) Subscription the module runs against. Leave unset to use the
    subscription from the environment (ARM_SUBSCRIPTION_ID).
  EOT
  type        = string
  default     = null
}

variable "tags" {
  description = <<-EOT
    (Optional) Extra tags to put on the storage account (and private
    endpoint, if created). The module always adds managed-by = opentofu.
  EOT
  type        = map(string)
  default     = {}
}
