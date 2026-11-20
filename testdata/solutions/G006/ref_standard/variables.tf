variable "name" {
  description = "Application name; the storage account is named after it, with a unique suffix."
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,30}$", var.name))
    error_message = "Use 2-31 lowercase letters, digits and hyphens, starting with a letter."
  }
}

variable "resource_group_name" {
  description = "The application's resource group for this environment, such as orders-staging. The account takes its location."
  type        = string
}

variable "containers" {
  description = "Blob containers to create. All are private."
  type        = set(string)
  default     = ["files"]
}

variable "readers" {
  description = "Principal IDs (managed identities, groups) that can read blobs."
  type        = set(string)
  default     = []
}

variable "writers" {
  description = "Principal IDs (managed identities, groups) that can read, write and delete blobs."
  type        = set(string)
  default     = []
}

variable "log_analytics_workspace_id" {
  description = "Log Analytics workspace that receives blob read, write and delete logs. Null sends none."
  type        = string
  default     = null
}

variable "malware_scanning" {
  description = "Scan uploaded blobs for malware with Microsoft Defender for Storage (billed per GB scanned)."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags applied to the storage account."
  type        = map(string)
  default     = {}
}
