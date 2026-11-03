# ---------------------------------------------------------------------------
# Identifiers & placement — decided per environment/instance by the DBA team
# ---------------------------------------------------------------------------

variable "name" {
  description = "Base name for the Cloud SQL instance. Must be unique within the project."
  type        = string
  nullable    = false
}

variable "project_id" {
  description = "GCP project ID that owns the instance."
  type        = string
  nullable    = false
}

variable "region" {
  description = "Region for the primary instance."
  type        = string
  nullable    = false
}

# ---------------------------------------------------------------------------
# Engine & capacity — the DBA team's to decide
# ---------------------------------------------------------------------------

variable "postgres_version" {
  description = "Cloud SQL for PostgreSQL major version (e.g. POSTGRES_15, POSTGRES_16)."
  type        = string
  default     = "POSTGRES_15"
}

variable "tier" {
  description = "Machine tier, e.g. db-custom-2-7680. If null, a default is derived from vcpu/memory."
  type        = string
  default     = null
}

variable "cpu" {
  description = "vCPU count for a db-custom tier (used only when tier is null)."
  type        = number
  default     = 2
}

variable "memory_mb" {
  description = "Memory in MB for a db-custom tier (used only when tier is null)."
  type        = number
  default     = 7680
}

variable "disk_size_gb" {
  description = "Provisioned disk size in GB."
  type        = number
  default     = 100
}

variable "disk_autoresize" {
  description = "Allow automatic storage increase."
  type        = bool
  default     = true
}

variable "disk_autoresize_limit_gb" {
  description = "Upper bound for automatic storage increase. 0 means no bound."
  type        = number
  default     = 0
}

variable "disk_type" {
  description = "Disk type: PD_SSD or PD_HDD."
  type        = string
  default     = "PD_SSD"
}

variable "availability_type" {
  description = "ZONAL or REGIONAL."
  type        = string
  default     = "ZONAL"
  validation {
    condition     = contains(["ZONAL", "REGIONAL"], var.availability_type)
    error_message = "availability_type must be ZONAL or REGIONAL."
  }
}

variable "zone" {
  description = "Preferred zone for a ZONAL primary instance. Ignored for REGIONAL."
  type        = string
  default     = null
}

variable "maintenance_day" {
  description = "Day of week for maintenance (1=Mon .. 7=Sun)."
  type        = number
  default     = 7
}

variable "maintenance_hour" {
  description = "Hour of day (UTC) for the maintenance window."
  type        = number
  default     = 4
}

# ---------------------------------------------------------------------------
# Networking — private-only, always. The network team has already configured
# private services access on each environment network, so we reference their
# allocated range.
# ---------------------------------------------------------------------------

variable "network_name" {
  description = "Name of the custom VPC network (apps-dev / apps-staging / apps-prod) to peer with."
  type        = string
  nullable    = false
}

variable "network_project_id" {
  description = "Project owning the VPC (shared VPC host project, if different)."
  type        = string
  default     = null
}

variable "allocated_ip_range" {
  description = "Name of the existing allocated IP range on the VPC that private services access uses."
  type        = string
  nullable    = false
}

variable "ipv4_enabled" {
  description = "Enable internal IPv4 connectivity. Private-only regardless of this flag."
  type        = bool
  default     = true
}

# ---------------------------------------------------------------------------
# Databases and users
# ---------------------------------------------------------------------------

variable "databases" {
  description = "Map of database name -> charset (or {} to create none)."
  type        = map(string)
  default     = {}
}

variable "iam_users" {
  description = "IAM users to grant database access. Keys are db names, values are lists of IAM principals (user: / serviceAccount:)."
  type        = map(list(string))
  default     = {}
}

# ---------------------------------------------------------------------------
# Labels — standardized by the module; owners can add environment-specific tags
# ---------------------------------------------------------------------------

variable "environment" {
  description = "Environment name, e.g. dev, staging, prod. Used in labels."
  type        = string
  default     = null
}

variable "owner_team" {
  description = "Owning team label (defaults to dba)."
  type        = string
  default     = "dba"
}

variable "additional_labels" {
  description = "Additional labels to apply to every resource."
  type        = map(string)
  default     = {}
}

# ---------------------------------------------------------------------------
# Flags — with secure, fixing defaults
# ---------------------------------------------------------------------------

variable "deletion_protection" {
  description = "Prevent accidental deletion of the instance."
  type        = bool
  default     = true
}

variable "backup_enabled" {
  description = "Enable automated daily backups with point-in-time recovery."
  type        = bool
  default     = true
}

variable "backup_start_time" {
  description = "HH:MM UTC start time for automated backups."
  type        = string
  default     = "03:00"
}

variable "backup_retention_days" {
  description = "Number of days to retain automated backups (1-365)."
  type        = number
  default     = 7
}

variable "point_in_time_recovery" {
  description = "Enable point-in-time recovery."
  type        = bool
  default     = true
}

variable "transaction_log_retention_days" {
  description = "Days to retain transaction logs for PITR (1-7)."
  type        = number
  default     = 7
}

variable "query_insights_enabled" {
  description = "Enable Query Insights."
  type        = bool
  default     = true
}

# ---------------------------------------------------------------------------
# Read replicas — optional, decided per environment
# ---------------------------------------------------------------------------

variable "replica_count" {
  description = "Number of read replicas to create (0 for none)."
  type        = number
  default     = 0
}

variable "replica_tier" {
  description = "Machine tier for read replicas. Defaults to the primary tier."
  type        = string
  default     = null
}

variable "replica_zones" {
  description = "Zones for read replicas, applied in order. Defaults to the same region as primary."
  type        = list(string)
  default     = []
}