# ---------------------------------------------------------------------------
# The three inputs an app team needs to fill in. Everything else is defaulted
# by the module.
# ---------------------------------------------------------------------------

variable "resource_group_name" {
  description = <<-EOT
    Name of the application's existing resource group for this environment
    (e.g. "orders-staging" or "orders-prod"). The storage account is created
    in this resource group and in the same Azure region as it.
  EOT
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9._()-]{1,80}$", var.resource_group_name))
    error_message = "resource_group_name must be a valid Azure resource group name (letters, digits, '.', '_', '(', ')', '-'; 1-80 characters)."
  }
}

variable "environment" {
  description = <<-EOT
    Environment this storage belongs to, e.g. "dev", "staging" or "prod".
    The module uses this to pick data-protection settings: "prod" gets
    zone-redundant storage and 30-day soft delete; other environments get
    locally-redundant storage and 7-day soft delete.
  EOT
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,15}$", var.environment))
    error_message = "environment must be lowercase, start with a letter, and contain only letters, digits and hyphens (max 16 characters), e.g. \"dev\", \"staging\", \"prod\"."
  }
}

variable "application_principal_id" {
  description = <<-EOT
    Object (principal) ID of the application's Entra ID identity (the managed
    identity or service principal the app uses on AKS / App Service). The
    module grants this identity "Storage Blob Data Contributor" on the
    account, so the app can read/write blobs with its Entra identity - no
    connection strings or access keys needed. Note: this is the object ID of
    the identity, not the application/client ID.
  EOT
  type        = string

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.application_principal_id))
    error_message = "application_principal_id must be a GUID: the object (principal) ID of the application's Entra ID identity."
  }
}

# ---------------------------------------------------------------------------
# Optional inputs. Teams can ignore these entirely.
# ---------------------------------------------------------------------------

variable "blob_containers" {
  description = <<-EOT
    Names of blob containers to create for the application's files (e.g.
    ["uploads", "reports"]). All containers are private - access is via
    Entra ID RBAC only, never anonymous. Container names must be lowercase
    letters, digits and hyphens, 3-63 characters.
  EOT
  type        = set(string)
  default     = []

  validation {
    condition     = alltrue([for c in var.blob_containers : can(regex("^[a-z0-9](-?[a-z0-9])*$", c)) && length(c) >= 3 && length(c) <= 63])
    error_message = "Each container name must be 3-63 characters of lowercase letters, digits and single hyphens, starting and ending with a letter or digit."
  }
}

variable "allowed_ip_ranges" {
  description = <<-EOT
    Optional public IPs / CIDR ranges allowed to reach the storage account.
    Leave empty (the default) to allow access from anywhere (authenticated
    Entra ID requests only). If set, the account switches to deny-by-default
    with these ranges allowed. Trusted Azure services (e.g. App Service)
    remain able to reach the account in both cases.
  EOT
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Extra tags to apply to all resources. The module always adds application, environment and managed-by tags."
  type        = map(string)
  default     = {}
}
