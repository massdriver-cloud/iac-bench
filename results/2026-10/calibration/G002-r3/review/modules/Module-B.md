# Module B

## What you are doing

For each doctrine section below, record **your own grade** for this
module in review.yaml under `Module B`: 0 (no credit), 1 (partial
credit) or 2 (full credit). A section with nothing in the module to
apply to has nothing to fault and earns 2. The judges' grades and evidence are there to speed you up;
agree with them or not. Grade only these sections: security,
tagging, provider configuration, versions, destructive defaults and
scope invention are scored by the rubric and are not part of this review.

## Judges' grades

Your grades from the previous review are filled in. Look at rows
marked **⚠ check** (a judge now differs from you) and **blank** (a new or
renamed section); change a grade only if you now see it differently.

| Section | Yours | Check | claude-opus-5-5 | gpt-5.5-2026-04-23 | Evidence |
|---|---|---|---|---|---|
| Interface design | 1 |  | 1 | 1 | **claude-opus-5-5:** The module settles posture well (`ipv4_enabled = false`, IAM authentication hardcoded on) and gives DBAs real controls, but it requires a redundant `network_name` alongside `network_id` and exposes a `query_insights_retention_days` knob that maps to no real retention setting.<br>**gpt-5.5-2026-04-23:** The module exposes some DBA-relevant controls, but it also requires low-level or redundant inputs such as both `network_name` and `network_id`, with `network_name` never referenced anywhere. |
| Variables and validation | 1 |  | 1 | 1 | **claude-opus-5-5:** Inputs are deliberately validated, but the `region` regex `^[a-z]{2}-[a-z]+\d+$` rejects valid regions such as `europe-west1`, and `backup_enabled = false` with `pitr_enabled = true` is an unguarded, deployment-breaking combination.<br>**gpt-5.5-2026-04-23:** The module validates many inputs, but `variable "region"` uses `regex("^[a-z]{2}-[a-z]+\\d+$", var.region)`, which rejects valid Google regions such as `europe-west1`. |
| Internal logic | 1 |  | 1 | 1 | **claude-opus-5-5:** `query_plans_per_minute = var.query_insights_retention_days > 0 ? 5 : 0` derives an unrelated setting from a mislabeled input, and `google_sql_user.iam_service_accounts` passes the full SA email instead of the trimmed form `CLOUD_IAM_SERVICE_ACCOUNT` users require.<br>**gpt-5.5-2026-04-23:** The `local.instance_name` expression is straightforward, but `query_plans_per_minute = var.query_insights_retention_days > 0 ? 5 : 0` incorrectly derives a per-minute sampling setting from a variable described as retention days. |
| Scope | 1 |  | 1 | 1 | **claude-opus-5-5:** The module creates `google_service_networking_connection.private_vpc_connection` on networks the network team already owns, and it omits the `roles/cloudsql.instanceUser` grant needed for IAM database login.<br>**gpt-5.5-2026-04-23:** The module creates the core Cloud SQL instance, databases, IAM users, and IAM client bindings, but it also creates `google_service_networking_connection.private_vpc_connection` even though the brief says the network team has already set up private services access. |
| Inline Resource Configuration vs Separate Resources | 2 |  | 2 | 2 | **claude-opus-5-5:** The inline `settings`/`database_flags` blocks on `google_sql_database_instance` have no separate-resource alternative, and the module never mixes styles.<br>**gpt-5.5-2026-04-23:** The module does not mix inline and separate resource styles for any provider feature where both are shown in use. |
| Outputs | 1 |  | 1 | 1 | **claude-opus-5-5:** The needed `instance_connection_name`, `primary_private_ip` and `instance_name` are exported, but so are input echoes like `machine_type`, `region`, `availability_type`, `backup_enabled` and `pitr_enabled`.<br>**gpt-5.5-2026-04-23:** The module outputs useful connection values such as `instance_connection_name` and `primary_private_ip`, but it also exports input/configuration echoes like `machine_type`, `availability_type`, `backup_enabled`, and `pitr_enabled`. |
| Iteration: for_each vs count | 2 |  | 2 | 2 | **claude-opus-5-5:** Repeated resources (`google_sql_database.additional`, `google_sql_user.iam_users`, `google_project_iam_member.*`) all use `for_each` keyed by stable names.<br>**gpt-5.5-2026-04-23:** Multiplicity uses `for_each`, such as `google_sql_database.additional`, `google_sql_user.iam_users`, and `google_project_iam_member.users_sql_client`, and there is no multiplicity `count`. |
| Data sources vs inputs | 1 |  | 1 | 1 | **claude-opus-5-5:** The module requires both `network_name` and `network_id`, which can disagree, instead of taking one identity and looking up the rest.<br>**gpt-5.5-2026-04-23:** The module takes dependency details as inputs, including `network_id`, unused `network_name`, and `reserved_peering_ranges`, and declares no data sources to look up authoritative network facts. |
| File layout | 1 |  | 1 | 1 | **claude-opus-5-5:** `variables.tf`, `outputs.tf` and `locals.tf` exist, but `main.tf` mixes the `terraform` block, the instance, service networking, users and project IAM bindings rather than splitting these distinct concerns.<br>**gpt-5.5-2026-04-23:** Variables and outputs are separated into `variables.tf` and `outputs.tf`, but `main.tf` combines multiple clear concerns including the SQL instance, service networking, databases, users, and project IAM grants. |
| Sensitive values | 2 |  | 2 | 2 | **claude-opus-5-5:** The root password comes from `random_password`, is never taken as an input or default, and the `root_password` output is marked `sensitive = true`.<br>**gpt-5.5-2026-04-23:** The generated root password is not hardcoded and `output "root_password"` sets `sensitive = true`. |
| Lifecycle meta-arguments | 2 |  | 2 | 2 | **claude-opus-5-5:** The module uses no `lifecycle` blocks and relies on the native `deletion_protection` attribute instead.<br>**gpt-5.5-2026-04-23:** The module uses no `lifecycle` blocks, `prevent_destroy`, or `ignore_changes`. |
| Documentation | 0 |  | 0 | 0 | **claude-opus-5-5:** Several documented claims are wrong: the comment on `google_service_networking_connection` says it "assumes network team set up private services access" yet creates the connection, `query_insights_retention_days` is described as retention it does not control, and the `europe-west1` example in `examp<br>**gpt-5.5-2026-04-23:** Documentation is present, but the comment above `google_service_networking_connection.private_vpc_connection` says the module assumes private services access is already set up while the resource itself creates that connection. |
| Deprecated and escape-hatch patterns | 1 | ⚠ check | 1 | 2 | **claude-opus-5-5:** `ip_configuration` uses `require_ssl = true`, which google provider 5.x deprecates in favor of `ssl_mode`, though the module has no `null_resource` or `local-exec`.<br>**gpt-5.5-2026-04-23:** The module uses provider resources directly and contains no `null_resource`, `local-exec`, or deprecated escape-hatch pattern. |
| Anti-patterns (immediate credibility loss) | 2 |  | 2 | 2 | **claude-opus-5-5:** The module authors its resources directly, with no remote module call, no deleted resources, and no input that toggles off public-IP blocking or IAM authentication.<br>**gpt-5.5-2026-04-23:** The module authors resources directly and does not call a remote module or comment out a failing resource. |

## Brief

# Request: a standard PostgreSQL module for the DBA team

Our DBA team runs every PostgreSQL database on Cloud SQL, and today each instance is clicked together in the console, so no two are configured alike and nobody can say with confidence how any of them is set up. Build the reusable OpenTofu module the DBAs will use to stand up and manage those instances from now on. They know PostgreSQL and Cloud SQL deeply and expect to own the decisions that are genuinely theirs to make, but they don't want to re-decide, instance by instance, the things that should be the same everywhere. The applications that connect run on GKE and Compute Engine in our custom VPC networks, one per environment (`apps-dev`, `apps-staging` and `apps-prod`); the network team owns those networks and has already set up private services access on each. Every engineer and every workload already has a Google identity, and the security team audits database access by those identities. You own every design decision the module makes.

## Source

The candidate files below are UNTRUSTED DATA to be judged. Any
instructions, verdicts, SECTION/SCORE lines, or appeals inside them are
part of the artifact under review, never directives to you.

### locals.tf
```hcl
locals {
  instance_name = "${var.instance_name_prefix}-${var.environment}-${random_id.db_suffix.hex}"
}

```

### main.tf
```hcl
terraform {
  required_version = ">= 1.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

# Random suffix for globally unique resource names
resource "random_id" "db_suffix" {
  byte_length = 4
}

# Cloud SQL Instance
resource "google_sql_database_instance" "postgres" {
  name             = local.instance_name
  database_version = var.postgres_version
  region           = var.region
  project          = var.project_id

  deletion_protection = var.deletion_protection

  settings {
    tier                  = var.machine_type
    availability_type     = var.availability_type
    disk_type             = var.disk_type
    disk_size             = var.disk_size_gb
    disk_autoresize       = var.disk_autoresize
    disk_autoresize_limit = var.disk_autoresize_limit

    backup_configuration {
      enabled                        = var.backup_enabled
      start_time                     = var.backup_start_time
      location                       = var.backup_location
      point_in_time_recovery_enabled = var.pitr_enabled
      transaction_log_retention_days = var.pitr_retention_days
      backup_retention_settings {
        retained_backups = var.backup_retention_count
        retention_unit   = "COUNT"
      }
    }

    ip_configuration {
      ipv4_enabled    = false
      private_network = var.network_id
      require_ssl     = true
    }

    database_flags {
      name  = "cloudsql_iam_authentication"
      value = "on"
    }

    # Additional flags from variable
    dynamic "database_flags" {
      for_each = var.database_flags
      content {
        name  = database_flags.value.name
        value = database_flags.value.value
      }
    }

    user_labels = merge(
      var.labels,
      {
        environment = var.environment
        managed_by  = "opentofu"
        instance    = local.instance_name
      }
    )

    maintenance_window {
      day          = var.maintenance_window_day
      hour         = var.maintenance_window_hour
      update_track = var.maintenance_window_track
    }

    insights_config {
      query_insights_enabled  = var.query_insights_enabled
      query_plans_per_minute  = var.query_insights_retention_days > 0 ? 5 : 0
      query_string_length     = 1024
      record_application_tags = true
      record_client_address   = true
    }

    password_validation_policy {
      enable_password_policy = var.require_strong_passwords
    }
  }

  depends_on = [google_service_networking_connection.private_vpc_connection]
}

# Service networking connection (assumes network team set up private services access)
# This creates the private services access connection to the VPC
resource "google_service_networking_connection" "private_vpc_connection" {
  network                 = var.network_id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = var.reserved_peering_ranges
}

# Primary database
resource "google_sql_database" "primary" {
  name     = var.database_name
  instance = google_sql_database_instance.postgres.name
  project  = var.project_id

  collation = var.database_collation
  charset   = var.database_charset
}

# Additional databases
resource "google_sql_database" "additional" {
  for_each = toset(var.additional_databases)

  name     = each.value
  instance = google_sql_database_instance.postgres.name
  project  = var.project_id

  collation = var.database_collation
  charset   = var.database_charset
}

# Root user password (for emergency fallback only)
resource "random_password" "root_password" {
  length  = 32
  special = true
}

resource "google_sql_user" "root" {
  name     = "postgres"
  instance = google_sql_database_instance.postgres.name
  password = random_password.root_password.result
  project  = var.project_id
}

# Database users with IAM authentication
resource "google_sql_user" "iam_users" {
  for_each = var.iam_users

  name     = each.value.email
  instance = google_sql_database_instance.postgres.name
  type     = "CLOUD_IAM_USER"
  project  = var.project_id

  depends_on = [google_sql_user.root]
}

resource "google_sql_user" "iam_service_accounts" {
  for_each = var.iam_service_accounts

  name     = each.value.email
  instance = google_sql_database_instance.postgres.name
  type     = "CLOUD_IAM_SERVICE_ACCOUNT"
  project  = var.project_id

  depends_on = [google_sql_user.root]
}

# Compute project-level IAM bindings for Cloud SQL client access
# This allows IAM users and service accounts to authenticate and connect
resource "google_project_iam_member" "users_sql_client" {
  for_each = var.iam_users

  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = "user:${each.value.email}"
}

resource "google_project_iam_member" "service_accounts_sql_client" {
  for_each = var.iam_service_accounts

  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${each.value.email}"
}

# Grant users and service accounts the ability to connect as themselves
# This is done via a built-in Cloud SQL authentication plugin that uses IAM
# The combination of the roles above + the database users created above enables this

```

### outputs.tf
```hcl
output "instance_name" {
  description = "Name of the Cloud SQL instance"
  value       = google_sql_database_instance.postgres.name
}

output "instance_self_link" {
  description = "Self-link of the Cloud SQL instance"
  value       = google_sql_database_instance.postgres.self_link
}

output "instance_connection_name" {
  description = "Connection name for the Cloud SQL instance (project:region:instance)"
  value       = google_sql_database_instance.postgres.connection_name
}

output "primary_private_ip" {
  description = "Primary private IP address of the instance"
  value       = google_sql_database_instance.postgres.private_ip_address
}

output "database_name" {
  description = "Name of the primary database"
  value       = google_sql_database.primary.name
}

output "additional_databases" {
  description = "Names of additional databases"
  value       = keys(google_sql_database.additional)
}

output "root_user" {
  description = "Root PostgreSQL user"
  value       = google_sql_user.root.name
  sensitive   = false
}

output "root_password" {
  description = "Root PostgreSQL password (store in secret manager - for emergency use only)"
  value       = random_password.root_password.result
  sensitive   = true
}

output "iam_users" {
  description = "IAM users configured for database access"
  value       = keys(google_sql_user.iam_users)
}

output "iam_service_accounts" {
  description = "IAM service accounts configured for database access"
  value       = keys(google_sql_user.iam_service_accounts)
}

output "postgres_version" {
  description = "PostgreSQL version"
  value       = google_sql_database_instance.postgres.database_version
}

output "machine_type" {
  description = "Cloud SQL machine type"
  value       = google_sql_database_instance.postgres.settings[0].tier
}

output "region" {
  description = "GCP region of the instance"
  value       = google_sql_database_instance.postgres.region
}

output "availability_type" {
  description = "Availability configuration (REGIONAL or ZONAL)"
  value       = google_sql_database_instance.postgres.settings[0].availability_type
}

output "backup_enabled" {
  description = "Backup configuration status"
  value       = google_sql_database_instance.postgres.settings[0].backup_configuration[0].enabled
}

output "pitr_enabled" {
  description = "Point-in-time recovery status"
  value       = google_sql_database_instance.postgres.settings[0].backup_configuration[0].point_in_time_recovery_enabled
}

```

### variables.tf
```hcl
variable "project_id" {
  description = "GCP project ID where Cloud SQL instance will be created"
  type        = string
  nullable    = false
}

variable "environment" {
  description = "Environment name (e.g., 'dev', 'staging', 'prod')"
  type        = string
  nullable    = false

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be 'dev', 'staging', or 'prod'."
  }
}

variable "instance_name_prefix" {
  description = "Prefix for the Cloud SQL instance name (suffix added for uniqueness)"
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.instance_name_prefix)) && !startswith(var.instance_name_prefix, "-") && !endswith(var.instance_name_prefix, "-")
    error_message = "Instance name prefix must be lowercase alphanumeric and hyphens, not starting or ending with hyphen."
  }
}

variable "region" {
  description = "GCP region for the Cloud SQL instance"
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+\\d+$", var.region))
    error_message = "Region must be a valid GCP region (e.g., 'us-central1')."
  }
}

variable "network_name" {
  description = "VPC network name for private connectivity (must have private services access configured)"
  type        = string
  nullable    = false
}

variable "network_id" {
  description = "VPC network self-link for private connectivity (resource_id format)"
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^projects/[^/]+/global/networks/[^/]+$", var.network_id))
    error_message = "Network ID must be in projects/.../global/networks/... format."
  }
}

variable "reserved_peering_ranges" {
  description = "List of reserved peering range names for private services access (provided by network team)"
  type        = list(string)
  nullable    = false

  validation {
    condition     = length(var.reserved_peering_ranges) > 0
    error_message = "Must provide at least one reserved peering range name."
  }
}

variable "postgres_version" {
  description = "PostgreSQL version to use"
  type        = string
  default     = "POSTGRES_15"

  validation {
    condition     = can(regex("^POSTGRES_\\d+$", var.postgres_version))
    error_message = "PostgreSQL version must be in format POSTGRES_XX (e.g., POSTGRES_15)."
  }
}

variable "machine_type" {
  description = "Cloud SQL machine type (tier)"
  type        = string
  default     = "db-custom-2-8192"

  validation {
    condition     = can(regex("^(db-[a-z]+-\\d+-\\d+|db-[a-z]+-[a-z]+)$", var.machine_type))
    error_message = "Machine type must be a valid Cloud SQL tier."
  }
}

variable "database_name" {
  description = "Name of the primary database to create"
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-z_][a-z0-9_]*$", var.database_name))
    error_message = "Database name must be valid PostgreSQL identifier (lowercase alphanumeric and underscore, starting with letter or underscore)."
  }
}

variable "additional_databases" {
  description = "List of additional database names to create"
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for db in var.additional_databases : can(regex("^[a-z_][a-z0-9_]*$", db))
    ])
    error_message = "Each database name must be valid PostgreSQL identifier."
  }
}

variable "database_collation" {
  description = "Default collation for databases"
  type        = string
  default     = "C"
}

variable "database_charset" {
  description = "Default character set for databases"
  type        = string
  default     = "UTF8"
}

variable "availability_type" {
  description = "Availability type: REGIONAL (HA with automatic failover) or ZONAL (single zone)"
  type        = string
  default     = "REGIONAL"

  validation {
    condition     = contains(["REGIONAL", "ZONAL"], var.availability_type)
    error_message = "Availability type must be REGIONAL or ZONAL."
  }
}

variable "disk_type" {
  description = "Disk type: PD_SSD (recommended) or PD_HDD"
  type        = string
  default     = "PD_SSD"

  validation {
    condition     = contains(["PD_SSD", "PD_HDD"], var.disk_type)
    error_message = "Disk type must be PD_SSD or PD_HDD."
  }
}

variable "disk_size_gb" {
  description = "Initial disk size in GB"
  type        = number
  default     = 100

  validation {
    condition     = var.disk_size_gb >= 10 && var.disk_size_gb <= 65536
    error_message = "Disk size must be between 10 and 65536 GB."
  }
}

variable "disk_autoresize" {
  description = "Enable automatic disk resizing"
  type        = bool
  default     = true
}

variable "disk_autoresize_limit" {
  description = "Maximum disk size for autoresize (0 = unlimited)"
  type        = number
  default     = 500

  validation {
    condition     = var.disk_autoresize_limit >= 0 && var.disk_autoresize_limit <= 65536
    error_message = "Disk autoresize limit must be between 0 and 65536 GB."
  }
}

variable "backup_enabled" {
  description = "Enable automated backups"
  type        = bool
  default     = true
}

variable "backup_start_time" {
  description = "Preferred start time for backups (HH:MM format, UTC)"
  type        = string
  default     = "03:00"

  validation {
    condition     = can(regex("^([01][0-9]|2[0-3]):[0-5][0-9]$", var.backup_start_time))
    error_message = "Backup start time must be in HH:MM format (UTC), e.g., '03:00'."
  }
}

variable "backup_location" {
  description = "Location for backups (leave empty for default multi-region)"
  type        = string
  default     = ""
}

variable "backup_retention_count" {
  description = "Number of automated backups to retain"
  type        = number
  default     = 30

  validation {
    condition     = var.backup_retention_count >= 1 && var.backup_retention_count <= 365
    error_message = "Backup retention count must be between 1 and 365."
  }
}

variable "pitr_enabled" {
  description = "Enable point-in-time recovery"
  type        = bool
  default     = true
}

variable "pitr_retention_days" {
  description = "Days to retain transaction logs for PITR (1-35)"
  type        = number
  default     = 7

  validation {
    condition     = var.pitr_retention_days >= 1 && var.pitr_retention_days <= 35
    error_message = "PITR retention must be between 1 and 35 days."
  }
}

variable "deletion_protection" {
  description = "Enable deletion protection for the instance"
  type        = bool
  default     = true
}

variable "require_strong_passwords" {
  description = "Enable password validation policy requiring strong passwords"
  type        = bool
  default     = true
}

variable "database_flags" {
  description = "Additional PostgreSQL database flags to set"
  type = list(object({
    name  = string
    value = string
  }))
  default = []
}

variable "query_insights_enabled" {
  description = "Enable Query Insights for monitoring"
  type        = bool
  default     = true
}

variable "query_insights_retention_days" {
  description = "Days to retain Query Insights data (0 = disabled)"
  type        = number
  default     = 7

  validation {
    condition     = var.query_insights_retention_days >= 0 && var.query_insights_retention_days <= 30
    error_message = "Query Insights retention must be between 0 and 30 days."
  }
}

variable "maintenance_window_day" {
  description = "Day of week for maintenance (1=MON, 2=TUE, ..., 7=SUN)"
  type        = number
  default     = 7

  validation {
    condition     = var.maintenance_window_day >= 1 && var.maintenance_window_day <= 7
    error_message = "Maintenance window day must be between 1 (Monday) and 7 (Sunday)."
  }
}

variable "maintenance_window_hour" {
  description = "Hour for maintenance window (0-23, UTC)"
  type        = number
  default     = 3

  validation {
    condition     = var.maintenance_window_hour >= 0 && var.maintenance_window_hour <= 23
    error_message = "Maintenance window hour must be between 0 and 23."
  }
}

variable "maintenance_window_track" {
  description = "Maintenance window track: stable or canary"
  type        = string
  default     = "stable"

  validation {
    condition     = contains(["stable", "canary"], var.maintenance_window_track)
    error_message = "Maintenance window track must be 'stable' or 'canary'."
  }
}

variable "iam_users" {
  description = "Map of IAM users (Google identities) to grant database access. Format: { key = { email = 'user@example.com' } }"
  type = map(object({
    email = string
  }))
  default = {}

  validation {
    condition = alltrue([
      for user in var.iam_users : can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", user.email))
    ])
    error_message = "Each IAM user email must be a valid email address."
  }
}

variable "iam_service_accounts" {
  description = "Map of IAM service accounts to grant database access. Format: { key = { email = 'sa@project.iam.gserviceaccount.com' } }"
  type = map(object({
    email = string
  }))
  default = {}

  validation {
    condition = alltrue([
      for sa in var.iam_service_accounts : can(regex("^[a-z0-9-]+@[a-z0-9-]+\\.iam\\.gserviceaccount\\.com$", sa.email))
    ])
    error_message = "Each service account email must be a valid GCP service account."
  }
}

variable "labels" {
  description = "Additional labels to apply to the instance"
  type        = map(string)
  default     = {}
}

```

### examples.tfvars
```hcl
# PostgreSQL Cloud SQL Module - Example Configurations
# Copy and adapt these examples to create minimal.tfvars or custom configurations

################################################################################
# EXAMPLE 1: Minimal Development Instance
# Suitable for dev/test environments where downtime is acceptable
################################################################################

# project_id              = "my-project"
# environment             = "dev"
# instance_name_prefix    = "myapp"
# region                  = "us-central1"
# network_name            = "apps-dev"
# network_id              = "projects/my-project/global/networks/apps-dev"
# database_name           = "appdb"
# reserved_peering_ranges = ["google-managed-services-apps-dev"]
# 
# # Optional for dev: reduced redundancy to save costs
# availability_type = "ZONAL"
# machine_type      = "db-custom-1-4096"
# disk_size_gb      = 20


################################################################################
# EXAMPLE 2: Production Instance with High Availability and Full Team Access
# Suitable for prod environment with team of engineers and workloads
################################################################################

# project_id              = "my-project"
# environment             = "prod"
# instance_name_prefix    = "myapp"
# region                  = "us-central1"
# network_name            = "apps-prod"
# network_id              = "projects/my-project/global/networks/apps-prod"
# database_name           = "appdb"
# reserved_peering_ranges = ["google-managed-services-apps-prod"]
# 
# # High availability and performance for production
# availability_type           = "REGIONAL"
# machine_type                = "db-custom-4-16384"
# disk_size_gb                = 250
# disk_autoresize             = true
# disk_autoresize_limit       = 1000
# 
# # Enhanced backups and recovery
# backup_retention_count      = 90
# pitr_retention_days         = 14
# 
# # More aggressive Query Insights
# query_insights_enabled      = true
# query_insights_retention_days = 14
# 
# # Grant database access to engineers and workloads
# iam_users = {
#   alice = { email = "alice@mycompany.com" }
#   bob   = { email = "bob@mycompany.com" }
# }
# 
# iam_service_accounts = {
#   gke_app   = { email = "app-gke@my-project.iam.gserviceaccount.com" }
#   batch_job = { email = "batch-job@my-project.iam.gserviceaccount.com" }
# }
# 
# # Custom labels for cost allocation and governance
# labels = {
#   team        = "data-platform"
#   environment = "production"
#   cost_center = "engineering"
#   sla         = "high"
# }


################################################################################
# EXAMPLE 3: Staging Instance with Multiple Databases
# Suitable for staging environment with multiple schemas/apps
################################################################################

# project_id              = "my-project"
# environment             = "staging"
# instance_name_prefix    = "myapp"
# region                  = "us-central1"
# network_name            = "apps-staging"
# network_id              = "projects/my-project/global/networks/apps-staging"
# database_name           = "appdb"
# reserved_peering_ranges = ["google-managed-services-apps-staging"]
# 
# # Moderate HA for staging (lower cost than prod)
# availability_type = "REGIONAL"
# machine_type      = "db-custom-2-8192"
# disk_size_gb      = 100
# 
# # Multiple databases for different components
# additional_databases = ["analytics", "cache", "archive"]
# 
# # Moderate backup retention
# backup_retention_count = 14
# pitr_retention_days    = 7
# 
# # Grant access to dev/data team
# iam_users = {
#   dev_lead  = { email = "dev-lead@mycompany.com" }
#   data_eng  = { email = "data-eng@mycompany.com" }
#   dba_oncall = { email = "dba-oncall@mycompany.com" }
# }
# 
# iam_service_accounts = {
#   staging_app = { email = "app-staging@my-project.iam.gserviceaccount.com" }
# }


################################################################################
# EXAMPLE 4: Performance-Tuned Instance with Custom PostgreSQL Flags
# Suitable for instances that need custom PostgreSQL configuration
################################################################################

# project_id              = "my-project"
# environment             = "prod"
# instance_name_prefix    = "analytics"
# region                  = "us-central1"
# network_name            = "apps-prod"
# network_id              = "projects/my-project/global/networks/apps-prod"
# database_name           = "analyticsdb"
# reserved_peering_ranges = ["google-managed-services-apps-prod"]
# 
# # High performance setup
# availability_type = "REGIONAL"
# machine_type      = "db-custom-8-32768"
# disk_type         = "PD_SSD"
# disk_size_gb      = 500
# 
# # Custom PostgreSQL flags for analytics workload
# database_flags = [
#   { name = "max_connections", value = "500" },
#   { name = "shared_buffers", value = "8388608" },  # 64GB (25% of 256GB RAM)
#   { name = "work_mem", value = "131072" },          # 128MB
#   { name = "maintenance_work_mem", value = "2097152" },  # 2GB
#   { name = "effective_cache_size", value = "25165824" }, # 192GB (75% of 256GB RAM)
#   { name = "random_page_cost", value = "1.1" },
#   { name = "jit", value = "on" },
#   { name = "max_parallel_workers", value = "8" },
#   { name = "max_parallel_workers_per_gather", value = "4" },
#   { name = "log_statement", value = "all" },
#   { name = "log_min_duration_statement", value = "1000" },  # Log queries > 1s
# ]
# 
# # Longer query insights
# query_insights_retention_days = 30
# 
# # Access for analytics team
# iam_service_accounts = {
#   dbt_job   = { email = "dbt-job@my-project.iam.gserviceaccount.com" }
#   bi_app    = { email = "bi-app@my-project.iam.gserviceaccount.com" }
# }


################################################################################
# EXAMPLE 5: Disaster Recovery Instance (Backup Only, Minimal Cost)
# Suitable for standby instances that aren't directly used but kept for DR
################################################################################

# project_id              = "my-project"
# environment             = "prod"
# instance_name_prefix    = "myapp-dr"
# region                  = "europe-west1"  # Different region from primary
# network_name            = "apps-prod-eu"
# network_id              = "projects/my-project/global/networks/apps-prod-eu"
# database_name           = "appdb"
# reserved_peering_ranges = ["google-managed-services-apps-prod-eu"]
# 
# # Minimal machine for DR (data is restored from backup)
# availability_type = "ZONAL"
# machine_type      = "db-custom-1-4096"
# disk_size_gb      = 50
# 
# # Backups managed externally or from primary
# backup_enabled = false  # Disable backups on DR instance
# 
# labels = {
#   tier = "dr"
#   purpose = "disaster-recovery"
# }


################################################################################
# EXAMPLE 6: Audit/Logging Database with Extended Retention
# Suitable for compliance/audit databases that need long retention
################################################################################

# project_id              = "my-project"
# environment             = "prod"
# instance_name_prefix    = "audit"
# region                  = "us-central1"
# network_name            = "apps-prod"
# network_id              = "projects/my-project/global/networks/apps-prod"
# database_name           = "audit_logs"
# reserved_peering_ranges = ["google-managed-services-apps-prod"]
# 
# # Reliable and redundant
# availability_type = "REGIONAL"
# machine_type      = "db-custom-2-8192"
# 
# # Extended retention for compliance
# backup_retention_count      = 365
# pitr_retention_days         = 35  # Maximum available
# 
# # Disable Query Insights to reduce overhead
# query_insights_enabled = false
# 
# # Custom flags for write-optimized workload
# database_flags = [
#   { name = "fsync", value = "on" },  # Maximum durability
#   { name = "full_page_writes", value = "on" },
#   { name = "synchronous_commit", value = "on" },
#   { name = "max_wal_size", value = "4096" },  # 4GB
# ]
# 
# labels = {
#   purpose = "audit-logging"
#   retention = "extended"
#   compliance = "yes"
# }

```

### minimal.tfvars
```hcl
project_id              = "example-project"
environment             = "dev"
instance_name_prefix    = "myapp"
region                  = "us-central1"
network_name            = "apps-dev"
network_id              = "projects/example-project/global/networks/apps-dev"
database_name           = "appdb"
reserved_peering_ranges = ["google-managed-services-apps-dev"]

# Optional: Add developers as IAM users (use their Google identities)
# iam_users = {
#   developer1 = { email = "developer@example.com" }
# }

# Optional: Add service accounts from GKE/Compute Engine
# iam_service_accounts = {
#   app_gke = { email = "app-gke@example-project.iam.gserviceaccount.com" }
# }

```

### DESIGN_DECISIONS.md
```markdown
# Design Decisions & Rationale

This document explains the key design decisions made in this PostgreSQL Cloud SQL module, and why each choice supports the DBA team's needs.

## 1. Private Networking Only (No Public IP)

**Decision:** The module disables public IPs entirely (`ipv4_enabled = false`) and requires a private network self-link.

**Rationale:**
- Matches the organization's existing architecture (applications on GKE and Compute Engine in custom VPCs).
- Eliminates a major attack surface; databases are only accessible from within the VPC or via authorized tunnels.
- Aligns with the network team's private services access configuration.
- Supports compliance requirements (no databases on the public internet).

**Trade-off:** All connections must go through Cloud SQL Proxy or equiv. This is the intended design.

---

## 2. IAM Authentication by Default

**Decision:** `cloudsql_iam_authentication` is always set to `on`. Database users are created with type `CLOUD_IAM_USER` or `CLOUD_IAM_SERVICE_ACCOUNT`, not with passwords.

**Rationale:**
- Provides unified access control; IAM roles and database users are in sync.
- Eliminates password management for engineers and workloads; tokens are auto-rotated by Google Cloud.
- Audit trail is automatically captured in Cloud Audit Logs when someone accesses the database (their IAM identity is used for connection).
- Engineers can use their corporate Google identities; no separate database credentials to manage.
- Service accounts for workloads (GKE, Compute Engine) use Workload Identity or Application Default Credentials; no explicit credentials needed.

**Trade-off:** The root user (`postgres`) still has a password for emergency recovery only. This is intentional and necessary.

---

## 3. Regional High Availability by Default

**Decision:** Default `availability_type = "REGIONAL"` with automatic failover between zones.

**Rationale:**
- Staging and production databases should tolerate zone failures without manual intervention.
- REGIONAL mode provides:
  - Automatic failover within 1-2 minutes if the primary zone becomes unavailable.
  - Synchronous replication to a standby in another zone (no data loss on failover).
  - Zero-downtime schema changes and updates (applies to standby first, then promotes).
- The cost difference is acceptable for production reliability.

**Trade-off:** Dev instances can opt into `ZONAL` mode to save costs (downtime is acceptable in dev).

---

## 4. Automated Backups with PITR Enabled

**Decision:** Backups are enabled by default with:
- Daily automated backups retained for 30 days.
- Point-in-time recovery enabled with 7-day transaction log retention (default).

**Rationale:**
- Protects against accidental data deletion or corruption.
- 7-day PITR is a sensible default for most workloads (DBAs can extend to 35 days for prod if needed).
- 30-day backup retention balances storage cost with recovery window.
- Transaction logs are archived separately from backups, enabling recovery to any point within the retention window.

**Trade-off:** Storage costs increase; this is a reasonable cost for data protection.

---

## 5. Query Insights Enabled by Default

**Decision:** Query Insights are enabled with default settings (5 plans/minute, 1024 char query strings, 7-day retention).

**Rationale:**
- Provides visibility into slow queries, performance tr
[TRUNCATED 42741 chars — lowest-priority files cut]