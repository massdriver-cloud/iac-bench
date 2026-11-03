# Module E

## What you are doing

For each doctrine section below, record **your own grade** for this
module in review.yaml under `Module E`: 0 (no credit), 1 (partial
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
| Interface design | 2 |  | 2 | 2 | **claude-opus-5-5:** The DBAs get the controls their discipline expects (`tier`, `edition`, `database_version`, `database_flags`, `maintenance_window`, backup retention), while settled decisions are made by the module: the network is derived from `environment` as `apps-${var.environment}`, `ipv4_enabled = false` is fixe<br>**gpt-5.5-2026-04-23:** The module exposes DBA-owned choices such as `var.database_version`, `var.tier`, `var.maintenance_window`, and IAM principal sets while encoding the brief’s fixed VPC convention in `local.network_name = "apps-${var.environment}"`. |
| Variables and validation | 1 | ⚠ check | 2 | 2 | **claude-opus-5-5:** Realistic mistakes are guarded with teaching messages, including the `environment` enum, `iam_service_accounts` requiring the `.gserviceaccount.com` suffix, `maintenance_window` ranges, and a precondition tying `transaction_log_retention_days` above 7 to ENTERPRISE_PLUS; no check rejects a valid val<br>**gpt-5.5-2026-04-23:** Inputs that consumers could realistically mistype are validated, including `var.environment`, `var.name`, `var.ssl_mode`, `var.maintenance_window`, and the edition/PITR compatibility precondition on `google_sql_database_instance.this`. |
| Internal logic | 2 |  | 2 | 2 | **claude-opus-5-5:** Readable locals derive values from concepts, such as `availability_type` and `backup_retained` from `local.is_prod`, `network_self_link` from `environment`, and the `sql_iam_users` map that trims service-account suffixes, without convoluted chains.<br>**gpt-5.5-2026-04-23:** `locals` compute inferred values such as `availability_type`, `backup_retained`, enforced database flags, merged labels, and IAM role bindings from higher-level inputs. |
| Scope | 2 |  | 2 | 2 | **claude-opus-5-5:** The module creates the instance with private-only networking, enforced SSL, backups with PITR, query insights, databases, IAM database users, and instance-conditioned `google_project_iam_member` login roles, which is proportionate to the brief without unrequested extras.<br>**gpt-5.5-2026-04-23:** The module creates the Cloud SQL instance, databases, IAM database users, and conditional IAM login role grants while configuring private IP, backups, PITR, maintenance, insights, and IAM authentication. |
| Inline Resource Configuration vs Separate Resources | 2 |  | 2 | 2 | **claude-opus-5-5:** The `database_flags`, `ip_configuration` and `backup_configuration` blocks exist only as inline settings of `google_sql_database_instance`, and databases and users use their separate `google_sql_database`/`google_sql_user` resources.<br>**gpt-5.5-2026-04-23:** The module does not mix inline and separate resources for the same repeatable provider-owned configuration; IAM grants are modeled as separate `google_project_iam_member` resources. |
| Outputs | 2 |  | 2 | 2 | **claude-opus-5-5:** The outputs cover what consumers need, namely `connection_name`, `private_ip_address`, `instance_name`, `self_link`, `databases`, and the `iam_database_users` role names, without dumping every attribute.<br>**gpt-5.5-2026-04-23:** Outputs include operationally useful values such as `connection_name`, `private_ip_address`, `self_link`, created `databases`, and `iam_database_users` without dumping every resource attribute. |
| Iteration: for_each vs count | 2 |  | 2 | 2 | **claude-opus-5-5:** Databases, IAM users and role bindings all use `for_each` over sets or maps, and `count` is never used.<br>**gpt-5.5-2026-04-23:** Multiplicity uses `for_each` on `google_sql_database.this`, `google_sql_user.iam`, and `google_project_iam_member.sql_login`, with no `count` used for indexed resources. |
| Data sources vs inputs | 2 |  | 2 | 2 | **claude-opus-5-5:** The module takes only the network's identity (via `environment` and `network_project_id`) and never asks for derived facts such as CIDRs that could conflict with the real network.<br>**gpt-5.5-2026-04-23:** The module does not require conflicting dependency facts such as both a VPC ID and CIDR; it derives `local.network_self_link` from `var.environment` and `var.network_project_id`. |
| File layout | 1 | ⚠ check | 2 | 1 | **claude-opus-5-5:** The module is split into `main.tf`, `variables.tf`, `outputs.tf` and `versions.tf`, with roughly 150 lines of core resources in `main.tf`.<br>**gpt-5.5-2026-04-23:** Variables and outputs are separated into `variables.tf` and `outputs.tf`, but distinct concerns including the Cloud SQL instance, databases, SQL users, and project IAM bindings are all kept together in `main.tf`. |
| Sensitive values | 2 |  | 2 | 2 | **claude-opus-5-5:** No secrets are handled at all, because the module creates only IAM-authenticated `google_sql_user` resources with no password-based built-in users.<br>**gpt-5.5-2026-04-23:** The module has no password or raw secret variables or outputs, and `google_sql_user.iam` creates only IAM-based users without passwords. |
| Lifecycle meta-arguments | 2 |  | 2 | 2 | **claude-opus-5-5:** The only lifecycle use is a validation `precondition`, and deletion safety relies on the native `deletion_protection`/`deletion_protection_enabled` attributes rather than `prevent_destroy`.<br>**gpt-5.5-2026-04-23:** The only `lifecycle` block on `google_sql_database_instance.this` contains a `precondition`, with no inappropriate `prevent_destroy` or `ignore_changes`. |
| Documentation | 2 |  | 2 | 2 | **claude-opus-5-5:** Every variable and output has an accurate description (e.g. `disk_size_gb` explains autoresize behaviour, `iam_database_users` explains GRANT usage), and short comments explain the enforced flags and the service-account name trimming.<br>**gpt-5.5-2026-04-23:** Every declared variable and output has a `description`, such as `var.transaction_log_retention_days` and output `connection_name`. |
| Deprecated and escape-hatch patterns | 2 |  | 2 | 2 | **claude-opus-5-5:** There is no `null_resource`, `local-exec`, or deprecated resource form, and the module uses current attributes such as `ssl_mode` and `edition`.<br>**gpt-5.5-2026-04-23:** The module contains no `null_resource`, `local-exec`, or deprecated escape-hatch resource pattern. |
| Anti-patterns (immediate credibility loss) | 2 |  | 2 | 2 | **claude-opus-5-5:** The resources are authored directly with no remote module call, and no input can undo the established posture: `ssl_mode` validation allows only encrypted modes, and the enforced flags override `database_flags`.<br>**gpt-5.5-2026-04-23:** The module authors concrete Google resources directly and contains no remote `module` block or input that overrides the enforced IAM authentication flags. |

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
  network_project_id = coalesce(var.network_project_id, var.project_id)
  network_name       = "apps-${var.environment}"
  network_self_link  = "projects/${local.network_project_id}/global/networks/${local.network_name}"

  is_prod           = var.environment == "prod"
  availability_type = coalesce(var.availability_type, local.is_prod ? "REGIONAL" : "ZONAL")
  backup_retained   = coalesce(var.backup_retained_count, local.is_prod ? 30 : 7)

  # Flags enforced on every instance: IAM database authentication and
  # connection auditing so access can be tied to Google identities.
  enforced_flags = {
    "cloudsql.iam_authentication" = "on"
    "log_connections"             = "on"
    "log_disconnections"          = "on"
  }
  database_flags = merge(var.database_flags, local.enforced_flags)

  labels = merge(var.labels, {
    environment = var.environment
    managed-by  = "opentofu"
  })

  # Cloud SQL IAM user names: service accounts drop the .gserviceaccount.com suffix.
  sql_iam_users = merge(
    { for u in var.iam_users : "user:${u}" => { name = u, type = "CLOUD_IAM_USER" } },
    { for sa in var.iam_service_accounts : "serviceAccount:${sa}" => { name = trimsuffix(sa, ".gserviceaccount.com"), type = "CLOUD_IAM_SERVICE_ACCOUNT" } },
    { for g in var.iam_groups : "group:${g}" => { name = g, type = "CLOUD_IAM_GROUP" } },
  )

  iam_role_bindings = var.grant_iam_login_roles ? {
    for pair in setproduct(keys(local.sql_iam_users), ["roles/cloudsql.client", "roles/cloudsql.instanceUser"]) :
    "${pair[0]}|${pair[1]}" => { member = pair[0], role = pair[1] }
  } : {}
}

resource "google_sql_database_instance" "this" {
  project             = var.project_id
  region              = var.region
  name                = var.name
  database_version    = var.database_version
  deletion_protection = var.deletion_protection

  settings {
    edition                     = var.edition
    tier                        = var.tier
    availability_type           = local.availability_type
    disk_type                   = var.disk_type
    disk_size                   = var.disk_size_gb
    disk_autoresize             = true
    disk_autoresize_limit       = var.disk_autoresize_limit_gb
    deletion_protection_enabled = var.deletion_protection
    user_labels                 = local.labels

    ip_configuration {
      ipv4_enabled                                  = false
      private_network                               = local.network_self_link
      allocated_ip_range                            = var.allocated_ip_range
      ssl_mode                                      = var.ssl_mode
      enable_private_path_for_google_cloud_services = true
    }

    dynamic "location_preference" {
      for_each = var.zone == null ? [] : [var.zone]
      content {
        zone = location_preference.value
      }
    }

    backup_configuration {
      enabled                        = true
      start_time                     = var.backup_start_time
      point_in_time_recovery_enabled = true
      transaction_log_retention_days = var.transaction_log_retention_days

      backup_retention_settings {
        retained_backups = local.backup_retained
        retention_unit   = "COUNT"
      }
    }

    maintenance_window {
      day          = var.maintenance_window.day
      hour         = var.maintenance_window.hour
      update_track = var.maintenance_window.update_track
    }

    insights_config {
      query_insights_enabled  = true
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
  }

  lifecycle {
    precondition {
      condition     = var.edition == "ENTERPRISE_PLUS" || var.transaction_log_retention_days <= 7
      error_message = "transaction_log_retention_days above 7 requires the ENTERPRISE_PLUS edition."
    }
  }
}

resource "google_sql_database" "this" {
  for_each = var.databases

  project  = var.project_id
  instance = google_sql_database_instance.this.name
  name     = each.value
}

# Database logins are Google identities only: no password-based built-in
# users are created by this module.
resource "google_sql_user" "iam" {
  for_each = local.sql_iam_users

  project  = var.project_id
  instance = google_sql_database_instance.this.name
  name     = each.value.name
  type     = each.value.type
}

resource "google_project_iam_member" "sql_login" {
  for_each = local.iam_role_bindings

  project = var.project_id
  role    = each.value.role
  member  = each.value.member

  condition {
    title       = "cloudsql-${var.name}"
    description = "Restrict ${each.value.role} to Cloud SQL instance ${var.name}"
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
  description = "Connection name (project:region:instance) for the Cloud SQL Auth Proxy / connectors."
  value       = google_sql_database_instance.this.connection_name
}

output "private_ip_address" {
  description = "Private IP of the instance on the apps-<environment> VPC."
  value       = google_sql_database_instance.this.private_ip_address
}

output "self_link" {
  description = "Instance self link."
  value       = google_sql_database_instance.this.self_link
}

output "network" {
  description = "VPC the instance is attached to."
  value       = local.network_self_link
}

output "databases" {
  description = "Databases created on the instance."
  value       = sort([for d in google_sql_database.this : d.name])
}

output "iam_database_users" {
  description = "Database user names for the IAM principals (use these as the PostgreSQL role names in GRANTs)."
  value       = { for k, u in google_sql_user.iam : k => u.name }
}

```

### variables.tf
```hcl
############################################
# Identity and placement (required)
############################################

variable "project_id" {
  description = "Project that hosts the Cloud SQL instance."
  type        = string
}

variable "region" {
  description = "Region for the instance (e.g. europe-west1)."
  type        = string
}

variable "name" {
  description = "Instance name. Lowercase letters, digits and hyphens; must start with a letter. Cloud SQL names cannot be reused for about a week after deletion."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,78}[a-z0-9]$", var.name))
    error_message = "name must be 2-80 chars, lowercase letters, digits and hyphens, start with a letter and not end with a hyphen."
  }
}

variable "environment" {
  description = "Environment the instance serves. Selects the VPC the instance is attached to (apps-<environment>) and drives environment-sensitive defaults."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "network_project_id" {
  description = "Project that owns the apps-<environment> VPC (e.g. a Shared VPC host). Defaults to project_id."
  type        = string
  default     = null
}

variable "allocated_ip_range" {
  description = "Name of a specific private services access range to allocate the instance IP from. Null lets Cloud SQL pick from any range on the network."
  type        = string
  default     = null
}

############################################
# Engine and sizing (DBA decisions)
############################################

variable "database_version" {
  description = "PostgreSQL major version, e.g. POSTGRES_16."
  type        = string
  default     = "POSTGRES_16"

  validation {
    condition     = can(regex("^POSTGRES_[0-9]+$", var.database_version))
    error_message = "database_version must be a PostgreSQL version such as POSTGRES_16."
  }
}

variable "edition" {
  description = "Cloud SQL edition: ENTERPRISE or ENTERPRISE_PLUS. The tier must be valid for the edition."
  type        = string
  default     = "ENTERPRISE"

  validation {
    condition     = contains(["ENTERPRISE", "ENTERPRISE_PLUS"], var.edition)
    error_message = "edition must be ENTERPRISE or ENTERPRISE_PLUS."
  }
}

variable "tier" {
  description = "Machine tier, e.g. db-custom-2-7680 (ENTERPRISE) or db-perf-optimized-N-2 (ENTERPRISE_PLUS)."
  type        = string
  default     = "db-custom-2-7680"
}

variable "availability_type" {
  description = "REGIONAL (HA with standby in a second zone) or ZONAL. Null means REGIONAL in prod and ZONAL elsewhere."
  type        = string
  default     = null

  validation {
    condition     = var.availability_type == null || contains(["REGIONAL", "ZONAL"], coalesce(var.availability_type, "ZONAL"))
    error_message = "availability_type must be REGIONAL, ZONAL or null."
  }
}

variable "zone" {
  description = "Preferred primary zone. Null lets Cloud SQL choose."
  type        = string
  default     = null
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

variable "disk_size_gb" {
  description = "Initial disk size in GB. With autoresize on, the disk only grows; later changes below the current size are ignored by Cloud SQL."
  type        = number
  default     = 20

  validation {
    condition     = var.disk_size_gb >= 10
    error_message = "disk_size_gb must be at least 10."
  }
}

variable "disk_autoresize_limit_gb" {
  description = "Upper bound for automatic storage growth in GB. 0 means no limit."
  type        = number
  default     = 0

  validation {
    condition     = var.disk_autoresize_limit_gb >= 0
    error_message = "disk_autoresize_limit_gb must be >= 0."
  }
}

variable "database_flags" {
  description = "PostgreSQL flags (name => value). Flags the module enforces for security/auditing (cloudsql.iam_authentication, log_connections, log_disconnections) cannot be overridden."
  type        = map(string)
  default     = {}
}

############################################
# Operations
############################################

variable "maintenance_window" {
  description = "Weekly maintenance window. day: 1=Mon..7=Sun; hour: 0-23 UTC; update_track: canary, stable or week5."
  type = object({
    day          = number
    hour         = number
    update_track = optional(string, "stable")
  })
  default = {
    day  = 7
    hour = 3
  }

  validation {
    condition = (
      var.maintenance_window.day >= 1 && var.maintenance_window.day <= 7 &&
      var.maintenance_window.hour >= 0 && var.maintenance_window.hour <= 23 &&
      contains(["canary", "stable", "week5"], var.maintenance_window.update_track)
    )
    error_message = "maintenance_window.day must be 1-7, hour 0-23, update_track canary|stable|week5."
  }
}

variable "backup_start_time" {
  description = "Daily backup start time (HH:MM, UTC)."
  type        = string
  default     = "01:00"

  validation {
    condition     = can(regex("^([01][0-9]|2[0-3]):[0-5][0-9]$", var.backup_start_time))
    error_message = "backup_start_time must be HH:MM in 24h format."
  }
}

variable "backup_retained_count" {
  description = "Number of automated daily backups to retain. Null means 30 in prod and 7 elsewhere."
  type        = number
  default     = null

  validation {
    condition     = var.backup_retained_count == null || (coalesce(var.backup_retained_count, 7) >= 1 && coalesce(var.backup_retained_count, 7) <= 365)
    error_message = "backup_retained_count must be between 1 and 365."
  }
}

variable "transaction_log_retention_days" {
  description = "Days of WAL retained for point-in-time recovery (1-7 for ENTERPRISE, up to 35 for ENTERPRISE_PLUS)."
  type        = number
  default     = 7

  validation {
    condition     = var.transaction_log_retention_days >= 1 && var.transaction_log_retention_days <= 35
    error_message = "transaction_log_retention_days must be between 1 and 35."
  }
}

variable "ssl_mode" {
  description = "Connection encryption requirement: ENCRYPTED_ONLY or TRUSTED_CLIENT_CERTIFICATE_REQUIRED. Unencrypted connections are never allowed."
  type        = string
  default     = "ENCRYPTED_ONLY"

  validation {
    condition     = contains(["ENCRYPTED_ONLY", "TRUSTED_CLIENT_CERTIFICATE_REQUIRED"], var.ssl_mode)
    error_message = "ssl_mode must be ENCRYPTED_ONLY or TRUSTED_CLIENT_CERTIFICATE_REQUIRED."
  }
}

variable "deletion_protection" {
  description = "Protect the instance from deletion (both in OpenTofu and at the Cloud SQL API). Set false and apply before destroying."
  type        = bool
  default     = true
}

variable "labels" {
  description = "Additional labels. environment and managed-by are always set by the module."
  type        = map(string)
  default     = {}
}

############################################
# Databases and access
############################################

variable "databases" {
  description = "Databases to create on the instance."
  type        = set(string)
  default     = []
}

variable "iam_users" {
  description = "Google user accounts (email) granted IAM database login on this instance."
  type        = set(string)
  default     = []

  validation {
    condition     = alltrue([for u in var.iam_users : can(regex("^[^@\\s]+@[^@\\s]+$", u)) && !endswith(u, ".gserviceaccount.com")])
    error_message = "iam_users must be user email addresses (use iam_service_accounts for service accounts)."
  }
}

variable "iam_service_accounts" {
  description = "Service account emails (workloads, e.g. GKE Workload Identity or GCE service accounts) granted IAM database login."
  type        = set(string)
  default     = []

  validation {
    condition     = alltrue([for sa in var.iam_service_accounts : endswith(sa, ".gserviceaccount.com")])
    error_message = "iam_service_accounts must be service account emails ending in .gserviceaccount.com."
  }
}

variable "iam_groups" {
  description = "Google group emails whose members are granted IAM database login."
  type        = set(string)
  default     = []

  validation {
    condition     = alltrue([for g in var.iam_groups : can(regex("^[^@\\s]+@[^@\\s]+$", g))])
    error_message = "iam_groups must be email addresses."
  }
}

variable "grant_iam_login_roles" {
  description = "Grant roles/cloudsql.client and roles/cloudsql.instanceUser to the IAM principals, conditioned to this instance. Disable if access is granted elsewhere."
  type        = bool
  default     = true
}

```

### versions.tf
```hcl
terraform {
  required_version = ">= 1.6.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 6.0, < 8.0"
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
region      = "europe-west1"
name        = "orders-dev"
environment = "dev"

```