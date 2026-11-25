# =============================================================================
# Required Inputs — Application Identity & Placement
# =============================================================================

variable "application_name" {
  description = <<-EOT
    Short name of the application (for example, "orders" or "billing-api").
    Used to generate a globally unique, Azure-compliant storage account name and standard tags.
  EOT
  type        = string
  nullable    = false

  validation {
    condition = (
      can(regex("^[a-z0-9][a-z0-9-]{0,30}[a-z0-9]$", var.application_name)) &&
      length(replace(var.application_name, "-", "")) >= 2
    )
    error_message = "application_name must be 2-32 characters, lowercase alphanumeric with optional hyphens, starting and ending with a letter or number, and contain at least 2 alphanumeric characters."
  }
}

variable "environment" {
  description = <<-EOT
    Deployment environment for this application instance: "dev", "test", "staging", or "prod".
    Drives environment-aware defaults for redundancy, soft-delete retention, point-in-time restore,
    noncurrent version cleanup, and accidental-deletion locks.
  EOT
  type        = string
  nullable    = false

  validation {
    condition     = contains(["dev", "test", "staging", "prod"], var.environment)
    error_message = "environment must be one of: \"dev\", \"test\", \"staging\", \"prod\"."
  }
}

variable "resource_group_name" {
  description = <<-EOT
    Name of the application's existing Azure resource group for this environment
    (for example, "orders-staging" or "orders-prod").
  EOT
  type        = string
  nullable    = false

  validation {
    condition     = length(trimspace(var.resource_group_name)) >= 1 && length(var.resource_group_name) <= 90
    error_message = "resource_group_name must be a non-empty Azure resource group name (1-90 characters)."
  }
}

variable "location" {
  description = <<-EOT
    Azure region where the storage account will be created (for example, "eastus2" or "westeurope").
    Should match the region of the application's resource group.
  EOT
  type        = string
  nullable    = false

  validation {
    condition     = length(trimspace(var.location)) >= 2
    error_message = "location must be a non-empty Azure region name (for example, \"eastus2\")."
  }
}

variable "application_principal_id" {
  description = <<-EOT
    Entra ID object ID (principal ID) of the application's identity (Managed Identity or Service Principal
    used by AKS workload identity or App Service). Granted least-privilege blob data access via Azure RBAC.
  EOT
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.application_principal_id))
    error_message = "application_principal_id must be a valid Entra ID object ID UUID."
  }
}

variable "containers" {
  description = <<-EOT
    Blob containers to create for the application, keyed by container name.
    Pass an empty object `{}` for standard defaults, or optionally configure per-container
    lifecycle tiering and expiration (for example, expiring generated reports after 30 days
    or moving older media assets to Cool storage after 90 days).
  EOT
  type = map(object({
    tier_to_cool_after_days    = optional(number)
    tier_to_archive_after_days = optional(number)
    delete_after_days          = optional(number)
  }))
  nullable = false

  validation {
    condition     = length(var.containers) >= 1
    error_message = "At least one blob container must be specified in containers."
  }

  validation {
    condition = alltrue([
      for name in keys(var.containers) :
      can(regex("^[a-z0-9]([a-z0-9-]{1,61}[a-z0-9])$", name)) && !strcontains(name, "--")
    ])
    error_message = "Container names must be 3-63 characters, lowercase letters/numbers/hyphens only, start and end with a letter or number, and not contain consecutive hyphens (--)."
  }

  validation {
    condition = alltrue([
      for cfg in values(var.containers) : (
        (cfg.tier_to_cool_after_days == null || (cfg.tier_to_cool_after_days >= 1 && floor(cfg.tier_to_cool_after_days) == cfg.tier_to_cool_after_days)) &&
        (cfg.tier_to_archive_after_days == null || (cfg.tier_to_archive_after_days >= 1 && floor(cfg.tier_to_archive_after_days) == cfg.tier_to_archive_after_days)) &&
        (cfg.delete_after_days == null || (cfg.delete_after_days >= 1 && floor(cfg.delete_after_days) == cfg.delete_after_days)) &&
        (cfg.tier_to_cool_after_days == null || cfg.tier_to_archive_after_days == null || cfg.tier_to_cool_after_days < cfg.tier_to_archive_after_days) &&
        (cfg.tier_to_cool_after_days == null || cfg.delete_after_days == null || cfg.tier_to_cool_after_days < cfg.delete_after_days) &&
        (cfg.tier_to_archive_after_days == null || cfg.delete_after_days == null || cfg.tier_to_archive_after_days < cfg.delete_after_days)
      )
    ])
    error_message = "Container lifecycle day values must be positive integers in strictly increasing order: tier_to_cool_after_days < tier_to_archive_after_days < delete_after_days."
  }
}

# =============================================================================
# Optional Inputs — Access Control (Entra ID RBAC)
# =============================================================================

variable "application_role" {
  description = <<-EOT
    Azure RBAC data-plane role granted to application_principal_id on the storage account.
    Defaults to "Storage Blob Data Contributor" (read, write, and delete blobs).
  EOT
  type        = string
  default     = "Storage Blob Data Contributor"
  nullable    = false

  validation {
    condition = contains([
      "Storage Blob Data Reader",
      "Storage Blob Data Contributor",
      "Storage Blob Data Owner",
    ], var.application_role)
    error_message = "application_role must be a least-privilege Blob data role: \"Storage Blob Data Reader\", \"Storage Blob Data Contributor\", or \"Storage Blob Data Owner\"."
  }
}

variable "enable_user_delegation_sas" {
  description = <<-EOT
    Grant application_principal_id the "Storage Blob Delegator" role so the application can issue
    short-lived User Delegation SAS tokens (for example, for direct browser uploads of large images
    or videos) while keeping Shared Key authentication disabled.
  EOT
  type        = bool
  default     = false
  nullable    = false
}

variable "additional_role_assignments" {
  description = <<-EOT
    Optional map of additional Entra ID RBAC role assignments (for example, granting a reporting
    service read-only access to the "reports" container, or granting a support group read access).
    When container_name is omitted or null, the role is scoped to the entire storage account.
  EOT
  type = map(object({
    principal_id   = string
    role_name      = string
    container_name = optional(string)
    description    = optional(string)
  }))
  default  = {}
  nullable = false

  validation {
    condition = alltrue([
      for cfg in values(var.additional_role_assignments) :
      can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", cfg.principal_id))
    ])
    error_message = "Every principal_id in additional_role_assignments must be a valid Entra ID object ID UUID."
  }

  validation {
    condition = alltrue([
      for cfg in values(var.additional_role_assignments) :
      contains([
        "Storage Blob Data Reader",
        "Storage Blob Data Contributor",
        "Storage Blob Data Owner",
        "Storage Blob Delegator",
      ], cfg.role_name)
    ])
    error_message = "role_name in additional_role_assignments must be one of: \"Storage Blob Data Reader\", \"Storage Blob Data Contributor\", \"Storage Blob Data Owner\", or \"Storage Blob Delegator\"."
  }
}

# =============================================================================
# Optional Inputs — Networking (AKS & App Service Connectivity)
# =============================================================================

variable "allowed_subnet_ids" {
  description = <<-EOT
    List of Azure VNet subnet resource IDs allowed to access the storage account via VNet Service Endpoints
    (for example, your AKS node/pod subnet or App Service VNet integration subnet).
  EOT
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition = alltrue([
      for id in var.allowed_subnet_ids :
      can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.Network/virtualNetworks/[^/]+/subnets/[^/]+$", id))
    ])
    error_message = "Every entry in allowed_subnet_ids must be a valid Azure VNet subnet resource ID."
  }
}

variable "allowed_ip_ranges" {
  description = <<-EOT
    List of public IPv4 addresses or CIDR blocks allowed through the storage firewall
    (for example, NAT gateway egress IPs or corporate VPN egress ranges).
  EOT
  type        = list(string)
  default     = []
  nullable    = false
}

variable "private_endpoint" {
  description = <<-EOT
    Optional Private Endpoint configuration for private connectivity from AKS or App Service VNet integration.
    When configured, the module creates a blob Private Endpoint and disables public network access by default.
  EOT
  type = object({
    subnet_id           = string
    private_dns_zone_id = optional(string)
  })
  default = null

  validation {
    condition = (
      var.private_endpoint == null ||
      can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.Network/virtualNetworks/[^/]+/subnets/[^/]+$", var.private_endpoint.subnet_id))
    )
    error_message = "private_endpoint.subnet_id must be a valid Azure VNet subnet resource ID."
  }

  validation {
    condition = (
      var.private_endpoint == null ||
      var.private_endpoint.private_dns_zone_id == null ||
      can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.Network/privateDnsZones/[^/]+$", var.private_endpoint.private_dns_zone_id))
    )
    error_message = "private_endpoint.private_dns_zone_id must be a valid Azure Private DNS Zone resource ID."
  }
}

variable "public_network_access_enabled" {
  description = <<-EOT
    Override whether the storage account accepts traffic on its public endpoint.
    When null (default), automatically set to false if private_endpoint is configured, and true otherwise
    (protected by network_default_action = "Deny").
  EOT
  type        = bool
  default     = null
}

variable "network_default_action" {
  description = <<-EOT
    Default storage firewall action when no subnet or IP rule matches.
    Defaults to "Deny" (zero-trust posture). Set to "Allow" only if explicitly required for workloads
    without VNet integration or Private Endpoints.
  EOT
  type        = string
  default     = "Deny"
  nullable    = false

  validation {
    condition     = contains(["Deny", "Allow"], var.network_default_action)
    error_message = "network_default_action must be either \"Deny\" or \"Allow\"."
  }
}

variable "network_bypass" {
  description = <<-EOT
    Trusted Azure services allowed to bypass the storage firewall when network_default_action is "Deny".
  EOT
  type        = list(string)
  default     = ["AzureServices", "Logging", "Metrics"]
  nullable    = false

  validation {
    condition = alltrue([
      for item in var.network_bypass :
      contains(["AzureServices", "Logging", "Metrics", "None"], item)
    ])
    error_message = "network_bypass entries must be valid Azure Storage bypass values: \"AzureServices\", \"Logging\", \"Metrics\", or \"None\"."
  }
}

# =============================================================================
# Optional Inputs — Resilience, Data Protection & Lifecycle Overrides
# =============================================================================

variable "replication_type" {
  description = <<-EOT
    Override the storage redundancy tier. When null (default), the module selects based on environment:
    LRS for dev/test, ZRS for staging, and GRS for prod.
  EOT
  type        = string
  default     = null

  validation {
    condition     = var.replication_type == null || contains(["LRS", "ZRS", "GRS", "GZRS", "RAGRS", "RAGZRS"], var.replication_type)
    error_message = "replication_type must be one of: \"LRS\", \"ZRS\", \"GRS\", \"GZRS\", \"RAGRS\", \"RAGZRS\"."
  }
}

variable "access_tier" {
  description = <<-EOT
    Default blob access tier for the storage account ("Hot" or "Cool").
    Defaults to "Hot", which is optimal for active application uploads, media, and reports.
  EOT
  type        = string
  default     = "Hot"
  nullable    = false

  validation {
    condition     = contains(["Hot", "Cool"], var.access_tier)
    error_message = "access_tier must be either \"Hot\" or \"Cool\"."
  }
}

variable "blob_soft_delete_days" {
  description = <<-EOT
    Number of days deleted blobs remain recoverable. When null (default): 7 days in non-prod, 30 days in prod.
  EOT
  type        = number
  default     = null

  validation {
    condition     = var.blob_soft_delete_days == null || (var.blob_soft_delete_days >= 1 && var.blob_soft_delete_days <= 365 && floor(var.blob_soft_delete_days) == var.blob_soft_delete_days)
    error_message = "blob_soft_delete_days must be an integer between 1 and 365."
  }
}

variable "container_soft_delete_days" {
  description = <<-EOT
    Number of days deleted containers remain recoverable. When null (default): 7 days in non-prod, 30 days in prod.
  EOT
  type        = number
  default     = null

  validation {
    condition     = var.container_soft_delete_days == null || (var.container_soft_delete_days >= 1 && var.container_soft_delete_days <= 365 && floor(var.container_soft_delete_days) == var.container_soft_delete_days)
    error_message = "container_soft_delete_days must be an integer between 1 and 365."
  }
}

variable "versioning_enabled" {
  description = <<-EOT
    Enable automatic blob versioning to protect against accidental overwrites.
    Defaults to true in all environments (paired with automatic cleanup of old versions).
  EOT
  type        = bool
  default     = true
  nullable    = false
}

variable "point_in_time_restore_days" {
  description = <<-EOT
    Override point-in-time restore window in days (must be strictly less than blob_soft_delete_days).
    When null (default): disabled in non-prod, 7 days in prod. Set to 0 to explicitly disable in prod.
  EOT
  type        = number
  default     = null

  validation {
    condition     = var.point_in_time_restore_days == null || (var.point_in_time_restore_days >= 0 && var.point_in_time_restore_days <= 364 && floor(var.point_in_time_restore_days) == var.point_in_time_restore_days)
    error_message = "point_in_time_restore_days must be an integer between 0 (disabled) and 364."
  }
}

variable "noncurrent_version_retention_days" {
  description = <<-EOT
    Days to retain previous (noncurrent) blob versions before automatic lifecycle deletion.
    When null (default): 30 days in non-prod, 90 days in prod.
  EOT
  type        = number
  default     = null

  validation {
    condition     = var.noncurrent_version_retention_days == null || (var.noncurrent_version_retention_days >= 1 && floor(var.noncurrent_version_retention_days) == var.noncurrent_version_retention_days)
    error_message = "noncurrent_version_retention_days must be a positive integer."
  }
}

variable "enable_delete_lock" {
  description = <<-EOT
    Place an Azure CanNotDelete management lock on the storage account.
    When null (default): disabled in non-prod, enabled in prod.
  EOT
  type        = bool
  default     = null
}

variable "additional_lifecycle_rules" {
  description = <<-EOT
    Optional prefix-based lifecycle rules for fine-grained tiering or expiration within containers
    (for example, prefix_match = ["uploads/tmp/"] with delete_after_days = 7).
  EOT
  type = list(object({
    name                       = string
    prefix_match               = list(string)
    tier_to_cool_after_days    = optional(number)
    tier_to_archive_after_days = optional(number)
    delete_after_days          = optional(number)
  }))
  default  = []
  nullable = false

  validation {
    condition = alltrue([
      for r in var.additional_lifecycle_rules : (
        length(trimspace(r.name)) >= 1 &&
        length(r.prefix_match) >= 1 &&
        (r.tier_to_cool_after_days != null || r.tier_to_archive_after_days != null || r.delete_after_days != null) &&
        (r.tier_to_cool_after_days == null || (r.tier_to_cool_after_days >= 1 && floor(r.tier_to_cool_after_days) == r.tier_to_cool_after_days)) &&
        (r.tier_to_archive_after_days == null || (r.tier_to_archive_after_days >= 1 && floor(r.tier_to_archive_after_days) == r.tier_to_archive_after_days)) &&
        (r.delete_after_days == null || (r.delete_after_days >= 1 && floor(r.delete_after_days) == r.delete_after_days)) &&
        (r.tier_to_cool_after_days == null || r.tier_to_archive_after_days == null || r.tier_to_cool_after_days < r.tier_to_archive_after_days) &&
        (r.tier_to_cool_after_days == null || r.delete_after_days == null || r.tier_to_cool_after_days < r.delete_after_days) &&
        (r.tier_to_archive_after_days == null || r.delete_after_days == null || r.tier_to_archive_after_days < r.delete_after_days)
      )
    ])
    error_message = "Each additional_lifecycle_rules entry must specify a name, at least one prefix_match, and at least one positive integer day threshold in strictly increasing order (cool < archive < delete)."
  }
}

variable "cors_rules" {
  description = <<-EOT
    Optional CORS rules for browser-based direct uploads or media access (for example, using
    short-lived User Delegation SAS tokens generated by the application).
  EOT
  type = list(object({
    allowed_headers    = list(string)
    allowed_methods    = list(string)
    allowed_origins    = list(string)
    exposed_headers    = optional(list(string), [])
    max_age_in_seconds = optional(number, 3600)
  }))
  default  = []
  nullable = false

  validation {
    condition = alltrue([
      for r in var.cors_rules : (
        length(r.allowed_origins) >= 1 &&
        length(r.allowed_methods) >= 1 &&
        r.max_age_in_seconds >= 0 &&
        alltrue([for m in r.allowed_methods : contains(["DELETE", "GET", "HEAD", "MERGE", "POST", "OPTIONS", "PUT", "PATCH"], m)])
      )
    ])
    error_message = "Each cors_rules entry must specify allowed_origins, valid HTTP allowed_methods (DELETE, GET, HEAD, MERGE, POST, OPTIONS, PUT, PATCH), and non-negative max_age_in_seconds."
  }
}

# =============================================================================
# Optional Inputs — Observability, Malware Scanning & Governance
# =============================================================================

variable "log_analytics_workspace_id" {
  description = <<-EOT
    Optional Log Analytics Workspace resource ID. When provided, enables Azure Monitor diagnostic
    settings for Blob read/write/delete audit logs and storage transaction metrics.
  EOT
  type        = string
  default     = null

  validation {
    condition = (
      var.log_analytics_workspace_id == null ||
      can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.OperationalInsights/workspaces/[^/]+$", var.log_analytics_workspace_id))
    )
    error_message = "log_analytics_workspace_id must be a valid Azure Log Analytics Workspace resource ID."
  }
}

variable "enable_malware_scanning" {
  description = <<-EOT
    Enable Microsoft Defender for Storage on-upload malware scanning. Recommended for applications
    accepting untrusted user uploads when Microsoft Defender for Cloud is active in the subscription.
  EOT
  type        = bool
  default     = false
  nullable    = false
}

variable "malware_scanning_cap_gb_per_month" {
  description = <<-EOT
    Monthly scanning cap in GB when enable_malware_scanning is true (prevents runaway scan costs).
  EOT
  type        = number
  default     = 5000
  nullable    = false

  validation {
    condition     = var.malware_scanning_cap_gb_per_month >= 1 && floor(var.malware_scanning_cap_gb_per_month) == var.malware_scanning_cap_gb_per_month
    error_message = "malware_scanning_cap_gb_per_month must be a positive integer."
  }
}

variable "name_suffix" {
  description = <<-EOT
    Optional 1-6 lowercase alphanumeric suffix override for the generated storage account name.
    When null (default), a deterministic 6-character suffix is derived from subscription, resource group,
    application, and environment. Only override if resolving a rare global Azure naming collision.
  EOT
  type        = string
  default     = null

  validation {
    condition     = var.name_suffix == null || can(regex("^[a-z0-9]{1,6}$", var.name_suffix))
    error_message = "name_suffix must be 1-6 lowercase alphanumeric characters."
  }
}

variable "owner" {
  description = "Optional team or contact identifier added as an 'owner' tag on all resources."
  type        = string
  default     = null
}

variable "cost_center" {
  description = "Optional FinOps cost center code added as a 'cost_center' tag on all resources."
  type        = string
  default     = null
}

variable "tags" {
  description = "Optional additional tags merged onto all created Azure resources."
  type        = map(string)
  default     = {}
  nullable    = false
}
