###############################################################################
# The inputs an application team actually fills in.
###############################################################################

variable "name" {
  description = "Short name of the application (or of this workload's storage, e.g. \"orders\" or \"orders-media\"). Used to derive the globally-unique storage account name, resource names and tags. Must be unique within the resource group."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,22}[a-z0-9]$", var.name))
    error_message = "name must be 3-24 characters: lowercase letters, digits and hyphens, starting and ending with a letter or digit (e.g. \"orders\")."
  }
}

variable "resource_group_name" {
  description = "The application's resource group in this environment, e.g. \"orders-staging\" or \"orders-prod\". Must already exist; the storage account is created in it."
  type        = string
}

variable "environment" {
  description = "Environment this instance runs in. One of \"dev\", \"test\", \"staging\", \"prod\". Drives module defaults such as replication (GRS in prod, LRS elsewhere) and the storage account name."
  type        = string

  validation {
    condition     = contains(["dev", "test", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, test, staging, prod."
  }
}

variable "app_identity_object_ids" {
  description = <<-EOT
    Object IDs (principal IDs) of the Entra ID identities the application uses
    to access its files: the managed identity of the App Service app and/or
    the user-assigned identity behind the AKS workload identity. Each identity
    is granted "Storage Blob Data Contributor" on the storage account, i.e.
    read, write and delete on the blobs in every container.

    In the Azure portal: your managed identity -> Overview -> "Object ID".
    In Terraform: azurerm_user_assigned_identity.<name>.principal_id.
  EOT
  type        = set(string)

  validation {
    condition     = length(var.app_identity_object_ids) > 0
    error_message = "Provide at least one application identity: the object ID of the application's managed identity."
  }

  validation {
    condition = alltrue([
      for object_id in var.app_identity_object_ids :
      can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", object_id))
    ])
    error_message = "Each entry in app_identity_object_ids must be an Entra ID object ID (a GUID)."
  }
}

###############################################################################
# Optional inputs: sensible defaults, override only with a reason.
###############################################################################

variable "location" {
  description = "Azure region for the storage account, e.g. \"westeurope\". Defaults to the location of the application's resource group - which is where the storage should live."
  type        = string
  default     = null
}

variable "containers" {
  description = "Blob containers to create for the application's files. The defaults cover the usual kinds of application data: user uploads (\"uploads\"), images and video (\"media\"), generated reports and exports (\"exports\")."
  type        = set(string)
  default     = ["uploads", "media", "exports"]

  validation {
    condition = alltrue([
      for container_name in var.containers :
      can(regex("^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$", container_name))
    ])
    error_message = "Container names must be 3-63 characters: lowercase letters, digits and hyphens, starting and ending with a letter or digit."
  }
}

variable "replication_type" {
  description = "Storage replication: LRS, ZRS, GRS, RAGRS or GZRS. Default is the module's judgment: GRS in prod, LRS elsewhere - non-production data rarely justifies paying for geo-replication."
  type        = string
  default     = null

  validation {
    condition     = contains(["LRS", "ZRS", "GRS", "RAGRS", "GZRS"], coalesce(var.replication_type, "LRS"))
    error_message = "replication_type must be one of: LRS, ZRS, GRS, RAGRS, GZRS."
  }
}

variable "allow_shared_key_access" {
  description = "Allow authorising requests with storage account keys or SAS tokens. Disabled by default: the applications authenticate with their Entra ID identities, and account keys/SAS are standing credentials that bypass Entra ID entirely. Only enable this for tooling that cannot use Entra ID (yet)."
  type        = bool
  default     = false
}

variable "allowed_ip_ranges" {
  description = "IPv4 addresses or CIDR ranges allowed to reach the storage account over the public endpoint, e.g. [\"203.0.113.0/24\"]. Empty (default) means the public endpoint accepts traffic from anywhere - every request still has to authenticate with Entra ID."
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for ip_range in var.allowed_ip_ranges :
      can(regex("^([0-9]{1,3}[.]){3}[0-9]{1,3}(/[0-9]{1,2})?$", ip_range))
    ])
    error_message = "allowed_ip_ranges entries must be IPv4 addresses or CIDR ranges, e.g. \"203.0.113.10\" or \"203.0.113.0/24\"."
  }
}

variable "public_network_access_enabled" {
  description = "Whether the storage account is reachable from the public internet. Default (null) lets the module decide: off as soon as private endpoints are configured, otherwise on - requests are always authenticated with Entra ID either way. Set to false explicitly to lock the account down to private access only."
  type        = bool
  default     = null
}

variable "private_endpoint_subnet_ids" {
  description = "Subnet IDs to create a blob private endpoint in, for applications that run inside a virtual network (VNet-injected App Service, private AKS cluster). One entry per subnet, e.g. [azurerm_subnet.storage.id]. Configuring this turns public network access off by default."
  type        = list(string)
  default     = []
}

variable "private_dns_zone_id" {
  description = "ID of an existing privatelink.blob.core.windows.net private DNS zone to register the private endpoints in. Leave null (default) and the module creates and manages its own zone, linked to each virtual network that hosts a private endpoint subnet."
  type        = string
  default     = null
}

variable "blob_lifecycle" {
  description = "Blob lifecycle policy, in days since the blob was last modified. Defaults: blobs untouched for 90 days move to the Cool tier (cheaper storage, slightly slower first byte); nothing is ever auto-deleted; blob versions are kept for 90 days. Set days_to_archive / days_to_delete to also archive or expire data - only for data you are certain you can regenerate or lose."
  type = object({
    days_to_cool          = optional(number)
    days_to_archive       = optional(number)
    days_to_delete        = optional(number)
    days_to_keep_versions = optional(number)
  })
  default = {
    days_to_cool          = 90
    days_to_archive       = null
    days_to_delete        = null
    days_to_keep_versions = 90
  }

  validation {
    condition = alltrue([
      coalesce(var.blob_lifecycle.days_to_cool, 90) >= 1,
      coalesce(var.blob_lifecycle.days_to_keep_versions, 90) >= 1,
      coalesce(var.blob_lifecycle.days_to_archive, 1000000) > coalesce(var.blob_lifecycle.days_to_cool, 90),
      coalesce(var.blob_lifecycle.days_to_delete, 1000000) > coalesce(var.blob_lifecycle.days_to_archive, coalesce(var.blob_lifecycle.days_to_cool, 90)),
    ])
    error_message = "Lifecycle days must be at least 1, and the stages must be ordered: days_to_cool < days_to_archive < days_to_delete (the later stages are optional)."
  }
}

variable "tags" {
  description = "Extra tags to apply to the resources, on top of the module's standard application/environment/managed-by tags."
  type        = map(string)
  default     = {}
}
