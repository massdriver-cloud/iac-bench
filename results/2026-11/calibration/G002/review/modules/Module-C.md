# Module C

## What you are doing

For each doctrine section below, record **your own grade** for this
module in review.yaml under `Module C`: 0 (no credit), 1 (partial
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
| Interface design | 2 |  | 2 | 2 | **claude-opus-5-5:** The DBA-owned decisions are exposed as inputs (`tier`, `edition`, `database_flags`, `pgaudit_log_classes`, backup and maintenance windows), while `environment` selects the `apps-<env>` VPC and sets HA and update-track defaults, and private IP, IAM auth and pgaudit are fixed rather than offered as kn<br>**gpt-5.5-2026-04-23:** The module exposes DBA-owned Cloud SQL decisions such as `tier`, `database_version`, `edition`, databases, and IAM identities while deriving the environment VPC with `local.private_network = "projects/${local.network_project}/global/networks/apps-${var.environment}"`. |
| Variables and validation | 1 | ⚠ check | 2 | 1 | **claude-opus-5-5:** Realistic mistakes are guarded: `environment`, `edition`, `backup_start_time` and `maintenance_window` have teaching error messages, `iam_service_accounts` must end in `.gserviceaccount.com`, and a precondition ties `point_in_time_recovery_days` above 7 to `ENTERPRISE_PLUS`.<br>**gpt-5.5-2026-04-23:** The module has deliberate validations such as `environment` and `maintenance_window`, but `disk_autoresize_limit_gb` has no validation to reject negative values or values below `disk_size_gb`, which can break deployment. |
| Internal logic | 2 |  | 2 | 2 | **claude-opus-5-5:** Readable locals do the inference: `private_network` is built from `environment`, `availability_type` and `update_track` fall back to prod-based defaults, and `db_users` normalizes the three identity lists, including trimming the service-account suffix.<br>**gpt-5.5-2026-04-23:** Locals such as `availability_type`, `update_track`, `database_flags`, `db_users`, and `access_grants` compute inferred values from higher-level inputs in readable steps. |
| Scope | 2 |  | 2 | 2 | **claude-opus-5-5:** The module creates the instance, its databases, IAM-only database users, and instance-scoped conditional `google_project_iam_member` grants, with CMEK option, backups, PITR and query insights, and adds no unrequested architecture.<br>**gpt-5.5-2026-04-23:** The module creates the Cloud SQL instance, databases, IAM database users, and conditional IAM grants through `google_sql_database_instance.this`, `google_sql_database.this`, `google_sql_user.iam`, and `google_project_iam_member.access`. |
| Inline Resource Configuration vs Separate Resources | 2 |  | 2 | 2 | **claude-opus-5-5:** The only inline blocks (`database_flags`, `ip_configuration`, `backup_configuration`) have no separate-resource alternative, and databases and users use dedicated `google_sql_database` and `google_sql_user` resources.<br>**gpt-5.5-2026-04-23:** The module does not mix inline and separate resource styles for any repeated configurable child resource, and uses separate resources for databases, SQL users, and IAM members. |
| Outputs | 2 |  | 2 | 2 | **claude-opus-5-5:** The outputs cover what consumers need to connect — `connection_name`, `private_ip_address`, `instance_name`, `database_names` and `iam_database_users` — without dumping every attribute.<br>**gpt-5.5-2026-04-23:** Outputs include the practical connection and consumption values `connection_name`, `private_ip_address`, `private_network`, `database_names`, and `iam_database_users`. |
| Iteration: for_each vs count | 2 |  | 2 | 2 | **claude-opus-5-5:** Databases, users and IAM grants all use `for_each` with stable keys (database names, emails, `member|role`), and `count` is never used.<br>**gpt-5.5-2026-04-23:** Multiplicity is modeled with `for_each` on `google_sql_database.this`, `google_sql_user.iam`, and `google_project_iam_member.access`, and no `count` is used. |
| Data sources vs inputs | 2 |  | 2 | 2 | **claude-opus-5-5:** The module takes only the network identity, via `environment` and `network_project_id`, and derives the network path rather than asking for redundant facts that could conflict.<br>**gpt-5.5-2026-04-23:** The module avoids asking for derived network facts such as a VPC CIDR and instead derives the private network identity from `environment` and `network_project_id` in `local.private_network`. |
| File layout | 2 | ⚠ check | 2 | 1 | **claude-opus-5-5:** Variables, outputs, versions and core resources sit in `variables.tf`, `outputs.tf`, `versions.tf` and `main.tf`, and the resources in `main.tf` form one cohesive instance bundle of moderate length.<br>**gpt-5.5-2026-04-23:** Variables and outputs are separated into `variables.tf` and `outputs.tf`, but `main.tf` combines the instance, database resources, SQL users, and project IAM access resources despite those being distinct concerns. |
| Sensitive values | 2 |  | 2 | 2 | **claude-opus-5-5:** No secrets are handled, since only IAM-authenticated users are created ("No built-in (password) users are managed here"), so no passwords exist as variables or outputs.<br>**gpt-5.5-2026-04-23:** The module accepts no raw passwords or secret values, using IAM identities such as `iam_users`, `iam_groups`, and `iam_service_accounts` instead. |
| Lifecycle meta-arguments | 2 |  | 2 | 2 | **claude-opus-5-5:** The only `lifecycle` use is a precondition, and deletion protection uses the native `deletion_protection` and `deletion_protection_enabled` attributes rather than `prevent_destroy` or `ignore_changes`.<br>**gpt-5.5-2026-04-23:** The only lifecycle block on `google_sql_database_instance.this` contains a `precondition`, with no inappropriate `prevent_destroy` or `ignore_changes`. |
| Documentation | 0 | ⚠ check | 2 | 2 | **claude-opus-5-5:** Every variable and output has an accurate description, and targeted comments explain non-obvious choices such as the service-account name suffix handling and flags applied last so they always win.<br>**gpt-5.5-2026-04-23:** Every variable and output has a `description`, and comments explain non-obvious behavior such as IAM database username derivation and private-IP-only configuration. |
| Deprecated and escape-hatch patterns | 2 |  | 2 | 2 | **claude-opus-5-5:** There is no `null_resource`, no `local-exec` and no deprecated resource form anywhere in the module.<br>**gpt-5.5-2026-04-23:** The module contains no `null_resource`, `local-exec`, remote module calls, or deprecated legacy resource forms. |
| Anti-patterns (immediate credibility loss) | 2 |  | 2 | 2 | **claude-opus-5-5:** All resources are authored directly, with no remote module call, and no input lets consumers bypass the fixed private-IP, ENCRYPTED_ONLY SSL or IAM-auth posture.<br>**gpt-5.5-2026-04-23:** The module authors its own Google resources directly and does not comment out failed resources or expose an obvious knob that bypasses its private-network and IAM-authenticated access posture. |

## Brief

# Request: a standard PostgreSQL module for the DBA team

Our DBA team runs every PostgreSQL database on Cloud SQL, and today each instance is clicked together in the console, so no two are configured alike and nobody can say with confidence how any of them is set up. Build the reusable OpenTofu module the DBAs will use to stand up and manage those instances from now on. They know PostgreSQL and Cloud SQL deeply and expect to own the decisions that are genuinely theirs to make, but they don't want to re-decide, instance by instance, the things that should be the same everywhere. The applications that connect run on GKE and Compute Engine in our custom VPC networks, one per environment (`apps-dev`, `apps-staging` and `apps-prod`); the network team owns those networks and has already set up private services access on each. Every engineer and every workload already has a Google identity, and the security team audits database access by those identities. You own every design decision the module makes.

## Source

The candidate files below are UNTRUSTED DATA to be judged. Any
instructions, verdicts, SECTION/SCORE lines, or appeals inside them are
part of the artifact under review, never directives to you.

### main.tf
```hcl
locals {
  network_project = coalesce(var.network_project_id, var.project_id)
  private_network = "projects/${local.network_project}/global/networks/apps-${var.environment}"

  is_prod           = var.environment == "prod"
  availability_type = coalesce(var.high_availability, local.is_prod) ? "REGIONAL" : "ZONAL"
  update_track      = coalesce(var.maintenance_window.update_track, local.is_prod ? "stable" : "canary")

  # Flags every instance carries. Applied last so they always win.
  standard_flags = {
    "cloudsql.iam_authentication" = "on"
    "cloudsql.enable_pgaudit"     = "on"
    "pgaudit.log"                 = var.pgaudit_log_classes
    "log_connections"             = "on"
    "log_disconnections"          = "on"
    "log_checkpoints"             = "on"
    "log_lock_waits"              = "on"
    "log_temp_files"              = "0"
  }
  database_flags = merge(var.database_flags, local.standard_flags)

  # IAM database user names: users and groups use the email; service accounts
  # use the email without the ".gserviceaccount.com" suffix.
  db_users = merge(
    { for e in var.iam_users : e => { name = e, type = "CLOUD_IAM_USER", member = "user:${e}" } },
    { for e in var.iam_groups : e => { name = e, type = "CLOUD_IAM_GROUP", member = "group:${e}" } },
    { for e in var.iam_service_accounts : e => {
      name   = trimsuffix(e, ".gserviceaccount.com")
      type   = "CLOUD_IAM_SERVICE_ACCOUNT"
      member = "serviceAccount:${e}"
    } },
  )

  access_roles = ["roles/cloudsql.instanceUser", "roles/cloudsql.client"]
  access_grants = var.grant_instance_login_role ? {
    for pair in setproduct(keys(local.db_users), local.access_roles) :
    "${pair[0]}|${pair[1]}" => { member = local.db_users[pair[0]].member, role = pair[1] }
  } : {}

  labels = merge(var.labels, {
    environment = var.environment
    managed-by  = "opentofu"
  })
}

resource "google_sql_database_instance" "this" {
  project             = var.project_id
  name                = var.name
  region              = var.region
  database_version    = var.database_version
  deletion_protection = var.deletion_protection
  encryption_key_name = var.kms_key_name

  settings {
    tier                        = var.tier
    edition                     = var.edition
    availability_type           = local.availability_type
    disk_type                   = var.disk_type
    disk_size                   = var.disk_size_gb
    disk_autoresize             = true
    disk_autoresize_limit       = var.disk_autoresize_limit_gb
    deletion_protection_enabled = var.deletion_protection
    user_labels                 = local.labels

    # Private IP only: no public address, no authorized networks.
    ip_configuration {
      ipv4_enabled    = false
      private_network = local.private_network
      ssl_mode        = "ENCRYPTED_ONLY"
    }

    backup_configuration {
      enabled                        = true
      start_time                     = var.backup_start_time
      point_in_time_recovery_enabled = true
      transaction_log_retention_days = var.point_in_time_recovery_days

      backup_retention_settings {
        retained_backups = var.backup_retention_count
        retention_unit   = "COUNT"
      }
    }

    maintenance_window {
      day          = var.maintenance_window.day
      hour         = var.maintenance_window.hour
      update_track = local.update_track
    }

    insights_config {
      query_insights_enabled  = true
      query_plans_per_minute  = 5
      query_string_length     = 1024
      record_application_tags = true
      record_client_address   = true
    }

    dynamic "database_flags" {
      for_each = local.database_flags
      content {
        name  = database_flags.key
        value = database_flags.value
      }
    }

    dynamic "location_preference" {
      for_each = var.zone == null ? [] : [var.zone]
      content {
        zone = location_preference.value
      }
    }
  }

  lifecycle {
    precondition {
      condition     = var.edition == "ENTERPRISE_PLUS" || var.point_in_time_recovery_days <= 7
      error_message = "point_in_time_recovery_days above 7 requires the ENTERPRISE_PLUS edition."
    }
  }
}

resource "google_sql_database" "this" {
  for_each = toset(var.databases)

  project  = var.project_id
  instance = google_sql_database_instance.this.name
  name     = each.value
}

# Only IAM-authenticated users are created, so every connection maps to a
# Google identity. No built-in (password) users are managed here.
resource "google_sql_user" "iam" {
  for_each = local.db_users

  project  = var.project_id
  instance = google_sql_database_instance.this.name
  name     = each.value.name
  type     = each.value.type
}

resource "google_project_iam_member" "access" {
  for_each = local.access_grants

  project = var.project_id
  role    = each.value.role
  member  = each.value.member

  condition {
    title       = "cloudsql-${var.name}-only"
    description = "Limited to Cloud SQL instance ${var.name}"
    expression  = "resource.type == \"sqladmin.googleapis.com/Instance\" && resource.name == \"projects/${var.project_id}/instances/${var.name}\""
  }
}

```

### outputs.tf
```hcl
output "instance_name" {
  description = "Cloud SQL instance name."
  value       = google_sql_database_instance.this.name
}

output "connection_name" {
  description = "Instance connection name (project:region:instance) for the Cloud SQL Auth Proxy and connectors."
  value       = google_sql_database_instance.this.connection_name
}

output "private_ip_address" {
  description = "Private IP address of the instance within the environment VPC."
  value       = google_sql_database_instance.this.private_ip_address
}

output "private_network" {
  description = "VPC the instance is attached to."
  value       = local.private_network
}

output "database_names" {
  description = "Databases created on the instance."
  value       = [for d in google_sql_database.this : d.name]
}

output "iam_database_users" {
  description = "IAM database user names created on the instance."
  value       = [for u in google_sql_user.iam : u.name]
}

```

### variables.tf
```hcl
############################################
# Placement
############################################

variable "project_id" {
  description = "Project that will own the Cloud SQL instance."
  type        = string
}

variable "region" {
  description = "Region for the instance. Must be a region where the environment's private services access range is usable."
  type        = string
}

variable "environment" {
  description = "Environment the instance serves. Selects the VPC (apps-dev, apps-staging, apps-prod) the instance is attached to privately."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "network_project_id" {
  description = "Project that hosts the apps-<environment> VPC (e.g. a Shared VPC host project). Defaults to project_id."
  type        = string
  default     = null
}

############################################
# Instance (DBA decisions)
############################################

variable "name" {
  description = "Name of the Cloud SQL instance. Instance names cannot be reused for about a week after deletion."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,96}[a-z0-9]$", var.name))
    error_message = "name must be lowercase letters, digits and hyphens, start with a letter and end with a letter or digit."
  }
}

variable "database_version" {
  description = "PostgreSQL major version, as a Cloud SQL version string."
  type        = string
  default     = "POSTGRES_16"

  validation {
    condition     = can(regex("^POSTGRES_[0-9]+$", var.database_version))
    error_message = "database_version must look like POSTGRES_16."
  }
}

variable "edition" {
  description = "Cloud SQL edition: ENTERPRISE or ENTERPRISE_PLUS."
  type        = string
  default     = "ENTERPRISE"

  validation {
    condition     = contains(["ENTERPRISE", "ENTERPRISE_PLUS"], var.edition)
    error_message = "edition must be ENTERPRISE or ENTERPRISE_PLUS."
  }
}

variable "tier" {
  description = "Machine tier, e.g. db-custom-2-7680 (Enterprise) or db-perf-optimized-N-4 (Enterprise Plus)."
  type        = string
}

variable "high_availability" {
  description = "Regional (HA) instance with automatic failover. Null means: on in prod, off elsewhere."
  type        = bool
  default     = null
}

variable "zone" {
  description = "Preferred primary zone. Null lets Cloud SQL choose."
  type        = string
  default     = null
}

variable "disk_size_gb" {
  description = "Initial data disk size in GB. Storage autoresize is always on, so this is a starting point."
  type        = number
  default     = 20

  validation {
    condition     = var.disk_size_gb >= 10
    error_message = "disk_size_gb must be at least 10."
  }
}

variable "disk_autoresize_limit_gb" {
  description = "Upper bound for storage autoresize in GB. 0 means no limit."
  type        = number
  default     = 0
}

variable "disk_type" {
  description = "PD_SSD or PD_HDD."
  type        = string
  default     = "PD_SSD"

  validation {
    condition     = contains(["PD_SSD", "PD_HDD"], var.disk_type)
    error_message = "disk_type must be PD_SSD or PD_HDD."
  }
}

variable "deletion_protection" {
  description = "Protect the instance from deletion by tofu and by the Cloud SQL API. On by default; turn off deliberately to tear down a disposable instance."
  type        = bool
  default     = true
}

variable "kms_key_name" {
  description = "Optional customer-managed encryption key (full resource ID) for the instance. Cannot be changed after creation. Null uses Google-managed encryption."
  type        = string
  default     = null
}

variable "database_flags" {
  description = "Additional PostgreSQL/Cloud SQL flags (name => value). Flags the module fixes for security and auditing cannot be overridden."
  type        = map(string)
  default     = {}

  validation {
    condition = length(setintersection(keys(var.database_flags), [
      "cloudsql.iam_authentication",
      "cloudsql.enable_pgaudit",
      "pgaudit.log",
      "log_connections",
      "log_disconnections",
      "log_checkpoints",
      "log_lock_waits",
      "log_temp_files",
      "ssl_min_protocol_version",
    ])) == 0
    error_message = "database_flags must not override module-managed flags (IAM auth, pgaudit, connection/lock/temp-file logging, ssl_min_protocol_version)."
  }
}

variable "pgaudit_log_classes" {
  description = "Statement classes recorded by pgaudit (value of pgaudit.log), e.g. \"ddl,role,write\". Auditing itself is always on."
  type        = string
  default     = "ddl,role,write"
}

############################################
# Backups and maintenance
############################################

variable "backup_start_time" {
  description = "Start of the daily backup window, HH:MM in UTC."
  type        = string
  default     = "03:00"

  validation {
    condition     = can(regex("^([01][0-9]|2[0-3]):[0-5][0-9]$", var.backup_start_time))
    error_message = "backup_start_time must be HH:MM (24h, UTC)."
  }
}

variable "backup_retention_count" {
  description = "Number of automated backups to retain."
  type        = number
  default     = 14

  validation {
    condition     = var.backup_retention_count >= 1
    error_message = "backup_retention_count must be at least 1."
  }
}

variable "point_in_time_recovery_days" {
  description = "Days of transaction log retained for point-in-time recovery. 1-7 on ENTERPRISE, up to 35 on ENTERPRISE_PLUS. Point-in-time recovery itself is always on."
  type        = number
  default     = 7

  validation {
    condition     = var.point_in_time_recovery_days >= 1 && var.point_in_time_recovery_days <= 35
    error_message = "point_in_time_recovery_days must be between 1 and 35."
  }
}

variable "maintenance_window" {
  description = "Maintenance window: day 1 (Mon) - 7 (Sun), hour 0-23 UTC, and update track (stable, canary or week5). Null track means: stable in prod, canary elsewhere."
  type = object({
    day          = number
    hour         = number
    update_track = optional(string)
  })
  default = {
    day  = 7
    hour = 4
  }

  validation {
    condition     = var.maintenance_window.day >= 1 && var.maintenance_window.day <= 7 && var.maintenance_window.hour >= 0 && var.maintenance_window.hour <= 23
    error_message = "maintenance_window.day must be 1-7 and hour 0-23."
  }

  validation {
    condition     = var.maintenance_window.update_track == null || contains(["stable", "canary", "week5"], coalesce(var.maintenance_window.update_track, "stable"))
    error_message = "maintenance_window.update_track must be stable, canary or week5."
  }
}

############################################
# Databases and access
############################################

variable "databases" {
  description = "Databases to create on the instance."
  type        = list(string)
  default     = []
}

variable "iam_users" {
  description = "Human users (Google account emails) allowed to log in with IAM database authentication."
  type        = list(string)
  default     = []
}

variable "iam_service_accounts" {
  description = "Service account emails for workloads allowed to log in with IAM database authentication."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for s in var.iam_service_accounts : endswith(s, ".gserviceaccount.com")])
    error_message = "iam_service_accounts must be full service account emails ending in .gserviceaccount.com."
  }
}

variable "iam_groups" {
  description = "Google group emails allowed to log in with IAM database authentication."
  type        = list(string)
  default     = []
}

variable "grant_instance_login_role" {
  description = "Grant roles/cloudsql.instanceUser and roles/cloudsql.client (scoped by IAM condition to this instance) to the listed identities. Turn off if access is granted elsewhere."
  type        = bool
  default     = true
}

variable "labels" {
  description = "Extra labels applied to the instance."
  type        = map(string)
  default     = {}
}

```

### versions.tf
```hcl
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 6.0.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

```

### minimal.tfvars
```hcl
project_id  = "example-project"
region      = "us-central1"
environment = "dev"
name        = "example-pg"
tier        = "db-custom-2-7680"

```