variable "storage_account_name" {
  description = "Globally unique storage account name: 3-24 lowercase letters and digits."
  type        = string
  validation {
    condition     = can(regex("^[a-z0-9]{3,24}$", var.storage_account_name))
    error_message = "Use 3-24 lowercase letters and digits."
  }
}

variable "resource_group_name" {
  description = "The application's resource group for this environment."
  type        = string
}

variable "location" {
  description = "Region for the account."
  type        = string
}

variable "account_kind" {
  description = "Storage account kind."
  type        = string
  default     = "StorageV2"
}

variable "account_tier" {
  description = "Performance tier: Standard or Premium."
  type        = string
  default     = "Standard"
}

variable "min_tls_version" {
  description = "Minimum TLS version clients may use."
  type        = string
  default     = "TLS1_2"
}

variable "key_vault_key_id" {
  description = "Key Vault key that encrypts the account."
  type        = string
}

variable "key_identity_id" {
  description = "User-assigned identity that can use the key."
  type        = string
}

variable "zone_redundant" {
  description = "Keep copies in three availability zones (ZRS) instead of one datacenter (LRS). Use for production."
  type        = bool
  default     = false
}

variable "versioning" {
  description = "Keep previous versions of overwritten blobs."
  type        = bool
  default     = false
}

variable "delete_after_days" {
  description = "Delete blobs this many days after they were last modified. Null keeps them."
  type        = number
  default     = null
}

variable "principal_ids" {
  description = "Principal IDs of the application identities that read and write blobs."
  type        = set(string)
  default     = []
}

variable "log_analytics_workspace_id" {
  description = "Log Analytics workspace for blob access logs. Null sends none."
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags for the storage account."
  type        = map(string)
  default     = {}
}
