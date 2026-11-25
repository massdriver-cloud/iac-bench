###############################################################################
# Required Inputs
###############################################################################

variable "application_name" {
  description = "The name of the application (e.g. 'orders'). Used in resource naming and tagging."
  type        = string
}

variable "environment" {
  description = "The deployment environment (e.g. 'staging', 'prod', 'dev'). Used in naming, tiering defaults, and tagging."
  type        = string
}

variable "resource_group_name" {
  description = "The name of the existing resource group for the application in this environment (e.g. 'orders-staging')."
  type        = string
}

variable "location" {
  description = "The Azure region where the storage account should be deployed (e.g. 'eastus')."
  type        = string
}

variable "principal_id" {
  description = "The Entra ID principal ID (object ID) of the application's identity (e.g. AKS Workload Identity or App Service Managed Identity) to grant storage access."
  type        = string
}

###############################################################################
# Storage Account Customization (with sensible defaults)
###############################################################################

variable "storage_account_name" {
  description = "Explicit name for the storage account. If omitted, a standard globally unique name (st<app><env><hash>) will be generated automatically."
  type        = string
  default     = null

  validation {
    condition     = var.storage_account_name == null || can(regex("^[a-z0-9]{3,24}$", var.storage_account_name))
    error_message = "Storage account name must be between 3 and 24 characters and consist only of lowercase alphanumeric characters."
  }
}

variable "account_tier" {
  description = "The tier to use for this storage account. Standard is recommended for general application files."
  type        = string
  default     = "Standard"

  validation {
    condition     = contains(["Standard", "Premium"], var.account_tier)
    error_message = "Account tier must be either 'Standard' or 'Premium'."
  }
}

variable "account_replication_type" {
  description = "The replication strategy for the storage account. Defaults to GRS for production environments and LRS for non-production environments."
  type        = string
  default     = null

  validation {
    condition     = var.account_replication_type == null || contains(["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"], var.account_replication_type != null ? var.account_replication_type : "LRS")
    error_message = "Account replication type must be one of: LRS, GRS, RAGRS, ZRS, GZRS, RAGZRS."
  }
}

variable "account_kind" {
  description = "The kind of storage account. Defaults to StorageV2 (general-purpose v2)."
  type        = string
  default     = "StorageV2"
}

variable "access_tier" {
  description = "The default access tier for BlobStorage and StorageV2 accounts. Defaults to Hot."
  type        = string
  default     = "Hot"

  validation {
    condition     = contains(["Hot", "Cool"], var.access_tier)
    error_message = "Access tier must be either 'Hot' or 'Cool'."
  }
}

###############################################################################
# Containers
###############################################################################

variable "containers" {
  description = "List of blob container names to create for application files (e.g. user uploads, images, exports)."
  type        = list(string)
  default     = ["uploads"]
}

variable "container_access_type" {
  description = "The access level configured for the containers. Defaults to 'private' to block anonymous public access."
  type        = string
  default     = "private"

  validation {
    condition     = contains(["private", "blob", "container"], var.container_access_type)
    error_message = "Container access type must be one of: private, blob, container."
  }
}

###############################################################################
# Identity & Access Control (RBAC)
###############################################################################

variable "role_definition_name" {
  description = "The built-in Azure RBAC role to grant the application identity. Defaults to 'Storage Blob Data Contributor'."
  type        = string
  default     = "Storage Blob Data Contributor"
}

variable "additional_principal_ids" {
  description = "Optional additional Entra ID principal IDs to grant the same storage role (e.g., secondary workload identities, pipeline service principals)."
  type        = list(string)
  default     = []
}

variable "role_assignments" {
  description = "Additional custom role assignments to create on the storage account: map of key => { principal_id, role_definition_name }."
  type = map(object({
    principal_id         = string
    role_definition_name = string
  }))
  default = {}
}

###############################################################################
# Security & Governance
###############################################################################

variable "allow_nested_items_to_be_public" {
  description = "Whether to allow blob public access. Defaults to false to enforce privacy by default."
  type        = bool
  default     = false
}

variable "shared_access_key_enabled" {
  description = "Whether the storage account permits shared key authentication. Defaults to true for compatibility while default_to_oauth_authentication enforces OAuth by default."
  type        = bool
  default     = true
}

variable "default_to_oauth_authentication" {
  description = "Ensures Azure Portal and API clients default to Entra ID (OAuth) authentication."
  type        = bool
  default     = true
}

variable "min_tls_version" {
  description = "The minimum supported TLS version for all storage requests. Defaults to TLS1_2."
  type        = string
  default     = "TLS1_2"
}

variable "https_traffic_only_enabled" {
  description = "Forces all incoming traffic to use HTTPS encryption in transit. Defaults to true."
  type        = bool
  default     = true
}

###############################################################################
# Data Protection (Soft Delete & Versioning)
###############################################################################

variable "blob_soft_delete_retention_days" {
  description = "Number of days to retain soft-deleted blobs for accidental deletion recovery. Set to 0 to disable."
  type        = number
  default     = 7
}

variable "container_soft_delete_retention_days" {
  description = "Number of days to retain soft-deleted containers for accidental deletion recovery. Set to 0 to disable."
  type        = number
  default     = 7
}

variable "versioning_enabled" {
  description = "Whether blob versioning is enabled on the storage account."
  type        = bool
  default     = false
}

###############################################################################
# Networking & Firewall
###############################################################################

variable "network_default_action" {
  description = "Default action when no network rules match. 'Allow' or 'Deny'."
  type        = string
  default     = "Allow"

  validation {
    condition     = contains(["Allow", "Deny"], var.network_default_action)
    error_message = "Network default action must be either 'Allow' or 'Deny'."
  }
}

variable "allowed_ip_ranges" {
  description = "List of public IP addresses or CIDR blocks authorized to access the storage account."
  type        = list(string)
  default     = []
}

variable "allowed_subnet_ids" {
  description = "List of virtual network subnet IDs authorized to access the storage account via service endpoints."
  type        = list(string)
  default     = []
}

variable "network_bypass" {
  description = "Traffic that bypasses network rules. Defaults to AzureServices, Logging, Metrics."
  type        = list(string)
  default     = ["AzureServices", "Logging", "Metrics"]
}

###############################################################################
# CORS Configuration
###############################################################################

variable "cors_rules" {
  description = "List of CORS rules for blob storage, useful for direct client-side uploads and downloads."
  type = list(object({
    allowed_headers    = list(string)
    allowed_methods    = list(string)
    allowed_origins    = list(string)
    exposed_headers    = list(string)
    max_age_in_seconds = number
  }))
  default = []
}

###############################################################################
# Lifecycle Management
###############################################################################

variable "lifecycle_cool_after_days" {
  description = "Number of days after modification to transition blobs to cool storage tier. 0 disables."
  type        = number
  default     = 0
}

variable "lifecycle_archive_after_days" {
  description = "Number of days after modification to transition blobs to archive storage tier. 0 disables."
  type        = number
  default     = 0
}

variable "lifecycle_delete_after_days" {
  description = "Number of days after modification to automatically delete blobs (e.g. ephemeral exports). 0 disables."
  type        = number
  default     = 0
}

variable "custom_lifecycle_rules" {
  description = "List of custom lifecycle rules with name, prefix_match, cool_after_days, archive_after_days, and delete_after_days."
  type = list(object({
    name               = string
    enabled            = optional(bool, true)
    prefix_match       = optional(list(string))
    cool_after_days    = optional(number)
    archive_after_days = optional(number)
    delete_after_days  = optional(number)
  }))
  default = []
}

###############################################################################
# Tagging
###############################################################################

variable "tags" {
  description = "Additional tags to apply to all resources. Standard tags (Application, Environment, ManagedBy) are added automatically."
  type        = map(string)
  default     = {}
}
