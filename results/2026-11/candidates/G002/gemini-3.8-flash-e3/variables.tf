###############################################################################
# Required Variables (Decisions the DBA must supply per instance)
###############################################################################

variable "name" {
  description = "The name of the Cloud SQL PostgreSQL instance."
  type        = string
}

variable "network" {
  description = "The VPC network to which the instance is connected via Private Services Access (e.g. 'apps-dev', 'apps-staging', 'apps-prod', or full network URI)."
  type        = string
}

###############################################################################
# Cloud Project and Location Decisions
###############################################################################

variable "project" {
  description = "The Google Cloud project ID where the instance will be created. If null, the Google provider project is used."
  type        = string
  default     = null
}

variable "region" {
  description = "The Google Cloud region where the instance will be created."
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "The preferred primary availability zone for the instance (e.g. 'us-central1-a'). If null, GCP selects the zone automatically."
  type        = string
  default     = null
}

variable "secondary_zone" {
  description = "The preferred secondary availability zone for failover when availability_type is 'REGIONAL'."
  type        = string
  default     = null
}

###############################################################################
# PostgreSQL Engine and Sizing Decisions (Owned by DBAs)
###############################################################################

variable "database_version" {
  description = "The PostgreSQL database engine version (e.g. 'POSTGRES_14', 'POSTGRES_15', 'POSTGRES_16')."
  type        = string
  default     = "POSTGRES_15"
}

variable "tier" {
  description = "The machine tier / compute instance type (e.g. 'db-custom-2-7680', 'db-custom-4-16384')."
  type        = string
  default     = "db-custom-2-7680"
}

variable "edition" {
  description = "The Cloud SQL edition: 'ENTERPRISE' or 'ENTERPRISE_PLUS'."
  type        = string
  default     = "ENTERPRISE"
}

variable "availability_type" {
  description = "High availability configuration: 'REGIONAL' (multi-zone failover) or 'ZONAL' (single zone)."
  type        = string
  default     = "REGIONAL"
}

variable "disk_size" {
  description = "The initial size of the data disk in gigabytes."
  type        = number
  default     = 50
}

variable "disk_type" {
  description = "The storage disk type: 'PD_SSD' or 'PD_HDD'."
  type        = string
  default     = "PD_SSD"
}

variable "disk_autoresize" {
  description = "Whether to enable automatic disk capacity resizing as storage fills up."
  type        = bool
  default     = true
}

variable "disk_autoresize_limit" {
  description = "Maximum disk size limit for automatic resizing in GB (0 = unlimited)."
  type        = number
  default     = 0
}

###############################################################################
# Networking Decisions
###############################################################################

variable "allocated_ip_range" {
  description = "Optional name of an allocated IP range in Private Services Access. If null, the default range is used."
  type        = string
  default     = null
}

variable "enable_private_path_for_google_cloud_services" {
  description = "Whether to allow Google Cloud services (such as BigQuery and Cloud Run) to access Cloud SQL privately."
  type        = bool
  default     = true
}

###############################################################################
# Backup and Maintenance Policy Decisions
###############################################################################

variable "backup_start_time" {
  description = "Start time for daily automated backups in UTC (HH:MM format)."
  type        = string
  default     = "03:00"
}

variable "backup_retention_count" {
  description = "The number of automated daily backups to retain."
  type        = number
  default     = 14
}

variable "transaction_log_retention_days" {
  description = "Number of days to retain transaction logs (WAL) for point-in-time recovery (1-7 days)."
  type        = number
  default     = 7
}

variable "maintenance_window_day" {
  description = "Day of week for scheduled maintenance (1-7, 1=Monday, 7=Sunday)."
  type        = number
  default     = 7
}

variable "maintenance_window_hour" {
  description = "Hour of day for scheduled maintenance in UTC (0-23)."
  type        = number
  default     = 3
}

variable "maintenance_window_track" {
  description = "Maintenance track: 'stable' or 'canary'."
  type        = string
  default     = "stable"
}

###############################################################################
# Monitoring and Query Insights
###############################################################################

variable "query_insights_enabled" {
  description = "Whether to enable Cloud SQL Query Insights for query performance diagnostics."
  type        = bool
  default     = true
}

variable "query_string_length" {
  description = "Maximum query length stored by Query Insights (256-4500)."
  type        = number
  default     = 1024
}

variable "record_application_tags" {
  description = "Whether Query Insights records application tags from connecting workloads."
  type        = bool
  default     = true
}

variable "record_client_address" {
  description = "Whether Query Insights records client IP addresses for security and audit traceability."
  type        = bool
  default     = true
}

variable "query_plans_per_minute" {
  description = "Number of query execution plans Query Insights captures per minute (0-20)."
  type        = number
  default     = 5
}

###############################################################################
# Database Flags and Auditing
###############################################################################

variable "database_flags" {
  description = "Map of custom PostgreSQL database flags to set on the instance. Overrides or supplements standard flags."
  type        = map(string)
  default     = {}
}

variable "pgaudit_log" {
  description = "Classes of statements logged by pgAudit (e.g. 'all', 'ddl, role, write')."
  type        = string
  default     = "all"
}

###############################################################################
# Lifecycle and Operational Settings
###############################################################################

variable "deletion_protection" {
  description = "Whether deletion protection is enabled. Set to false for disposable environments."
  type        = bool
  default     = false
}

variable "labels" {
  description = "A mapping of labels to assign to the Cloud SQL instance."
  type        = map(string)
  default     = {}
}

###############################################################################
# Databases and Identity Management
###############################################################################

variable "databases" {
  description = "List of database configurations to create on the instance."
  type = list(object({
    name      = string
    charset   = optional(string, "UTF8")
    collation = optional(string, "en_US.UTF8")
  }))
  default = []
}

variable "iam_users" {
  description = "Set of engineer Google account emails (users or groups) to create as Cloud SQL IAM database users."
  type        = set(string)
  default     = []
}

variable "iam_service_accounts" {
  description = "Set of workload Google service account emails to create as Cloud SQL IAM database service accounts."
  type        = set(string)
  default     = []
}

variable "additional_users" {
  description = "List of additional database users (built-in SQL accounts) to create."
  type = list(object({
    name     = string
    password = string
    type     = optional(string, "BUILT_IN")
  }))
  default = []
}

variable "grant_iam_roles" {
  description = "Whether to grant roles/cloudsql.instanceUser and roles/cloudsql.client to the specified IAM users and service accounts in the project."
  type        = bool
  default     = false
}

###############################################################################
# Read Replicas
###############################################################################

variable "read_replicas" {
  description = "Map of read replica configurations to create for this instance."
  type = map(object({
    region                = optional(string, null)
    zone                  = optional(string, null)
    tier                  = optional(string, null)
    availability_type     = optional(string, "ZONAL")
    disk_size             = optional(number, null)
    disk_type             = optional(string, "PD_SSD")
    disk_autoresize       = optional(bool, true)
    disk_autoresize_limit = optional(number, 0)
    database_flags        = optional(map(string), {})
    user_labels           = optional(map(string), {})
  }))
  default = {}
}
