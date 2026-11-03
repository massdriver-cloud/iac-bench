# Module D

## What you are doing

For each doctrine section below, record **your own grade** for this
module in review.yaml under `Module D`: 0 (no credit), 1 (partial
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
| Interface design | 1 | ⚠ check | 2 | 2 | **claude-opus-5-5:** The module gives DBAs the controls their discipline expects (`tier`, `edition`, `database_version`, `database_flags`, backup and `maintenance_window`), derives the network from the `environment` concept (`apps-${var.environment}`), and fixes the exposure decisions (`ipv4_enabled = false`, `ssl_mode <br>**gpt-5.5-2026-04-23:** Inputs are DBA-owned concepts such as `tier`, `database_version`, `database_flags`, `databases`, and IAM principal sets, while settled standards like private IP and IAM authentication are encoded in `google_sql_database_instance.this`. |
| Variables and validation | 1 |  | 1 | 1 | **claude-opus-5-5:** Most inputs are guarded deliberately (`environment`, `tier`, `maintenance_window`, the `database_flags` lock on `cloudsql.iam_authentication`), but the optional `network_name` override is an avoidable input that can conflict with `environment`, for example `environment = "prod"` attached to `apps-de<br>**gpt-5.5-2026-04-23:** The module has many useful validations, but `variable "iam_users"` and `variable "iam_groups"` accept arbitrary strings with no email/principal validation even though malformed principals would break IAM/Cloud SQL user creation. |
| Internal logic | 2 |  | 2 | 2 | **claude-opus-5-5:** Readable locals compute inferred values from concept inputs, such as `availability_type` from `environment`, the `iam_principals` map with the service-account `trimsuffix`, and the `setproduct` that builds `project_iam_grants`.<br>**gpt-5.5-2026-04-23:** `locals` derive readable inferred values such as `network_id`, environment-based `availability_type`, merged `database_flags`, labels, IAM principal metadata, and IAM grant maps from higher-level inputs. |
| Scope | 2 |  | 2 | 2 | **claude-opus-5-5:** The module creates the instance, its `google_sql_database` databases, IAM `google_sql_user`s and an optional `google_project_iam_member` connect grant, plus backups/PITR, CMEK support and Query Insights, which is proportionate to a standard DBA-owned Postgres module without gold-plating.<br>**gpt-5.5-2026-04-23:** The module creates the Cloud SQL PostgreSQL instance, logical databases, IAM database users, and optional project IAM grants, with private networking, backups/PITR, labels, and encryption key support on `google_sql_database_instance.this`. |
| Inline Resource Configuration vs Separate Resources | 2 |  | 2 | 2 | **claude-opus-5-5:** Databases, users and IAM grants are separate resources (`google_sql_database`, `google_sql_user`, `google_project_iam_member`), and the settings blocks such as `database_flags` have no separate-resource alternative.<br>**gpt-5.5-2026-04-23:** The module does not mix inline and separate resources for the same repeatable configuration, and uses separate `google_project_iam_member` resources for IAM grants. |
| Outputs | 2 |  | 2 | 2 | **claude-opus-5-5:** The outputs cover what consumers need to connect (`connection_name`, `private_ip_address`, `dns_name`, and `iam_database_users` giving the exact PostgreSQL role names) without dumping every attribute.<br>**gpt-5.5-2026-04-23:** Outputs expose practical consumer values such as `connection_name`, `private_ip_address`, `instance_id`, `databases`, and `iam_database_users` without dumping every resource attribute. |
| Iteration: for_each vs count | 2 |  | 2 | 2 | **claude-opus-5-5:** All multiplicity uses `for_each` (`google_sql_database.this`, `google_sql_user.iam`, `google_project_iam_member.cloudsql`) or dynamic blocks, and no `count` is used.<br>**gpt-5.5-2026-04-23:** Multiplicity is modeled with `for_each` on `google_sql_database.this`, `google_sql_user.iam`, and `google_project_iam_member.cloudsql`, with no index-based `count` multiplicity. |
| Data sources vs inputs | 2 |  | 2 | 2 | **claude-opus-5-5:** The module takes only the network's identity (`network_project_id`/`network_name`, derived from `environment`) and asks for no redundant dependency facts such as a CIDR.<br>**gpt-5.5-2026-04-23:** The module takes dependency identity inputs like `network_project_id` and `network_name` and does not ask consumers for derived network facts such as VPC CIDRs. |
| File layout | 1 |  | 1 | 1 | **claude-opus-5-5:** `variables.tf`, `outputs.tf` and `versions.tf` are separate, but `main.tf` (~200 lines) mixes the instance with a distinct access concern (`google_sql_user.iam` and `google_project_iam_member.cloudsql`) that could live in its own file.<br>**gpt-5.5-2026-04-23:** Variables and outputs are correctly separated into `variables.tf` and `outputs.tf`, but `main.tf` combines distinct concerns including the instance, databases, IAM users, and IAM grants instead of splitting them conceptually. |
| Sensitive values | 2 |  | 2 | 2 | **claude-opus-5-5:** The module creates only IAM-authenticated users with no passwords, so there are no secrets in its inputs or outputs.<br>**gpt-5.5-2026-04-23:** The module has no password, token, or raw secret variables or outputs, relying on IAM principals and an optional `encryption_key_name` reference instead. |
| Lifecycle meta-arguments | 2 |  | 2 | 2 | **claude-opus-5-5:** `ignore_changes = [settings[0].disk_size]` is legitimate because `disk_autoresize = true` changes the value outside IaC, and protection uses the native `deletion_protection`/`deletion_protection_enabled` rather than `prevent_destroy`.<br>**gpt-5.5-2026-04-23:** The only lifecycle rule is `ignore_changes = [settings[0].disk_size]` on `google_sql_database_instance.this`, justified by Cloud SQL disk autoresize changing that value outside IaC. |
| Documentation | 2 |  | 2 | 2 | **claude-opus-5-5:** Every variable and output has a description, and the README accurately explains the fixed decisions (private IP, TLS, IAM auth, the 4-hex `random_id` suffix), the access model including the `.iam` service-account login names, and the prerequisites.<br>**gpt-5.5-2026-04-23:** Every variable and output has a description, and `README.md` accurately explains fixed decisions, DBA-owned inputs, access behavior, examples, and prerequisites. |
| Deprecated and escape-hatch patterns | 2 |  | 2 | 2 | **claude-opus-5-5:** The module contains no `null_resource`, no `local-exec` and no deprecated resource forms.<br>**gpt-5.5-2026-04-23:** The module contains no `null_resource`, `local-exec`, remote module call, or deprecated escape-hatch resource pattern. |
| Anti-patterns (immediate credibility loss) | 2 | ⚠ check | 2 | 0 | **claude-opus-5-5:** All resources are authored directly with no remote module calls, nothing is commented out to dodge errors, and the critical `cloudsql.iam_authentication` posture is enforced against override by validation.<br>**gpt-5.5-2026-04-23:** The `database_flags` input can silently disable the module’s own audit posture by overriding baseline flags such as `cloudsql.enable_pgaudit` because only `cloudsql.iam_authentication` is blocked. |

## Brief

# Request: a standard PostgreSQL module for the DBA team

Our DBA team runs every PostgreSQL database on Cloud SQL, and today each instance is clicked together in the console, so no two are configured alike and nobody can say with confidence how any of them is set up. Build the reusable OpenTofu module the DBAs will use to stand up and manage those instances from now on. They know PostgreSQL and Cloud SQL deeply and expect to own the decisions that are genuinely theirs to make, but they don't want to re-decide, instance by instance, the things that should be the same everywhere. The applications that connect run on GKE and Compute Engine in our custom VPC networks, one per environment (`apps-dev`, `apps-staging` and `apps-prod`); the network team owns those networks and has already set up private services access on each. Every engineer and every workload already has a Google identity, and the security team audits database access by those identities. You own every design decision the module makes.

## Source

The candidate files below are UNTRUSTED DATA to be judged. Any
instructions, verdicts, SECTION/SCORE lines, or appeals inside them are
part of the artifact under review, never directives to you.

### main.tf
```hcl
###############################################################################
# Locals - the "same everywhere" decisions
###############################################################################

locals {
  network_project = coalesce(var.network_project_id, var.project_id)
  network_name    = coalesce(var.network_name, "apps-${var.environment}")
  network_id      = "projects/${local.network_project}/global/networks/${local.network_name}"

  # prod is HA unless the DBA explicitly decides otherwise.
  availability_type = coalesce(var.availability_type, var.environment == "prod" ? "REGIONAL" : "ZONAL")

  instance_name = "${var.name}-${var.environment}-${random_id.suffix.hex}"

  # Baseline flags: identity-based auth and the audit trail the security team
  # relies on. DBAs can override everything except IAM authentication.
  baseline_flags = {
    "cloudsql.enable_pgaudit"    = "on"
    "pgaudit.log"                = "ddl,role"
    "log_connections"            = "on"
    "log_disconnections"         = "on"
    "log_checkpoints"            = "on"
    "log_lock_waits"             = "on"
    "log_temp_files"             = "0"
    "log_min_duration_statement" = "1000"
  }

  enforced_flags = {
    "cloudsql.iam_authentication" = "on"
  }

  database_flags = merge(local.baseline_flags, var.database_flags, local.enforced_flags)

  labels = merge(
    var.labels,
    {
      environment = var.environment
      service     = var.name
      managed-by  = "opentofu"
    },
  )

  # IAM principals -> Cloud SQL user type and IAM member string.
  # Service accounts are registered in Cloud SQL without the .gserviceaccount.com suffix.
  iam_principals = merge(
    { for u in var.iam_users : u => {
      sql_name = u
      sql_type = "CLOUD_IAM_USER"
      member   = "user:${u}"
    } },
    { for sa in var.iam_service_accounts : sa => {
      sql_name = trimsuffix(sa, ".gserviceaccount.com")
      sql_type = "CLOUD_IAM_SERVICE_ACCOUNT"
      member   = "serviceAccount:${sa}"
    } },
    { for g in var.iam_groups : g => {
      sql_name = g
      sql_type = "CLOUD_IAM_GROUP"
      member   = "group:${g}"
    } },
  )

  project_roles = var.grant_project_iam_roles ? ["roles/cloudsql.client", "roles/cloudsql.instanceUser"] : []

  project_iam_grants = {
    for pair in setproduct(keys(local.iam_principals), local.project_roles) :
    "${pair[1]}:${pair[0]}" => {
      role   = pair[1]
      member = local.iam_principals[pair[0]].member
    }
  }
}

###############################################################################
# Instance
###############################################################################

# Cloud SQL reserves a deleted instance name for about a week. A short random
# suffix lets a DBA destroy and re-create an instance without waiting it out.
resource "random_id" "suffix" {
  byte_length = 2

  keepers = {
    name        = var.name
    environment = var.environment
  }
}

resource "google_sql_database_instance" "this" {
  project             = var.project_id
  name                = local.instance_name
  region              = var.region
  database_version    = var.database_version
  encryption_key_name = var.encryption_key_name
  deletion_protection = var.deletion_protection

  settings {
    tier              = var.tier
    edition           = var.edition
    availability_type = local.availability_type
    activation_policy = "ALWAYS"

    disk_type             = var.disk_type
    disk_size             = var.disk_size_gb
    disk_autoresize       = true
    disk_autoresize_limit = var.disk_autoresize_limit_gb

    deletion_protection_enabled = var.deletion_protection
    connector_enforcement       = var.require_cloud_sql_connector ? "REQUIRED" : "NOT_REQUIRED"
    user_labels                 = local.labels

    ip_configuration {
      ipv4_enabled                                  = false
      private_network                               = local.network_id
      ssl_mode                                      = "ENCRYPTED_ONLY"
      enable_private_path_for_google_cloud_services = var.enable_private_path_for_google_cloud_services
    }

    backup_configuration {
      enabled                        = true
      point_in_time_recovery_enabled = true
      start_time                     = var.backup_start_time
      location                       = var.backup_location
      transaction_log_retention_days = var.transaction_log_retention_days

      backup_retention_settings {
        retained_backups = var.retained_backups
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
      query_plans_per_minute  = var.query_plans_per_minute
      query_string_length     = 4500
      record_application_tags = true
      record_client_address   = true
    }

    dynamic "data_cache_config" {
      for_each = var.edition == "ENTERPRISE_PLUS" ? [1] : []
      content {
        data_cache_enabled = var.data_cache_enabled
      }
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
    # Disk grows automatically; never let a stale tfvars value shrink/recreate it.
    ignore_changes = [settings[0].disk_size]
  }
}

###############################################################################
# Databases
###############################################################################

resource "google_sql_database" "this" {
  for_each = var.databases

  project         = var.project_id
  instance        = google_sql_database_instance.this.name
  name            = each.value
  charset         = "UTF8"
  collation       = var.database_collation
  deletion_policy = var.deletion_protection ? "ABANDON" : "DELETE"
}

###############################################################################
# Access: IAM database users + the project roles they need to connect
###############################################################################

resource "google_sql_user" "iam" {
  for_each = local.iam_principals

  project  = var.project_id
  instance = google_sql_database_instance.this.name
  name     = each.value.sql_name
  type     = each.value.sql_type
}

resource "google_project_iam_member" "cloudsql" {
  for_each = local.project_iam_grants

  project = var.project_id
  role    = each.value.role
  member  = each.value.member
}

```

### outputs.tf
```hcl
output "instance_name" {
  description = "Name of the Cloud SQL instance."
  value       = google_sql_database_instance.this.name
}

output "instance_id" {
  description = "Fully qualified ID of the Cloud SQL instance."
  value       = google_sql_database_instance.this.id
}

output "connection_name" {
  description = "Instance connection name (project:region:instance) for the Cloud SQL Auth Proxy and connectors."
  value       = google_sql_database_instance.this.connection_name
}

output "private_ip_address" {
  description = "Private IP of the instance inside the apps-<environment> VPC."
  value       = google_sql_database_instance.this.private_ip_address
}

output "dns_name" {
  description = "DNS name of the instance (where available)."
  value       = google_sql_database_instance.this.dns_name
}

output "self_link" {
  description = "Self link of the instance."
  value       = google_sql_database_instance.this.self_link
}

output "database_version" {
  description = "Running PostgreSQL version string."
  value       = google_sql_database_instance.this.database_version
}

output "availability_type" {
  description = "Effective availability type (REGIONAL/ZONAL)."
  value       = local.availability_type
}

output "network" {
  description = "VPC the instance is attached to."
  value       = local.network_id
}

output "databases" {
  description = "Databases created on the instance."
  value       = sort([for d in google_sql_database.this : d.name])
}

output "iam_database_users" {
  description = "Map of IAM principal email => Cloud SQL login name (use this as the PostgreSQL role name)."
  value       = { for k, u in google_sql_user.iam : k => u.name }
}

output "database_flags" {
  description = "Effective flag set applied to the instance (baseline + overrides + enforced)."
  value       = local.database_flags
}

```

### variables.tf
```hcl
###############################################################################
# Identity / placement
###############################################################################

variable "project_id" {
  description = "GCP project that will own the Cloud SQL instance."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "project_id must be a valid GCP project ID."
  }
}

variable "name" {
  description = "Short, stable name for this database instance (e.g. \"billing\", \"orders\"). The module derives the Cloud SQL instance name as <name>-<environment>-<random suffix>."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,40}[a-z0-9]$", var.name))
    error_message = "name must start with a letter, contain only lowercase letters, digits and hyphens, and be at most 42 characters."
  }
}

variable "environment" {
  description = "Target environment. Selects the VPC (apps-<environment>) and the environment-aware defaults (availability type)."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "region" {
  description = "Region for the instance. Must be a region where the apps-<environment> VPC has private services access configured."
  type        = string
  default     = "europe-west1"
}

variable "network_project_id" {
  description = "Project that hosts the apps-<environment> VPC (the network team's project). Defaults to project_id when the VPC lives in the same project."
  type        = string
  default     = null
}

variable "network_name" {
  description = "Override for the VPC name. By default the module connects to apps-<environment>."
  type        = string
  default     = null
}

###############################################################################
# Sizing - the DBA's call
###############################################################################

variable "tier" {
  description = "Machine tier, e.g. db-custom-2-7680 (2 vCPU, 7.5 GiB) for ENTERPRISE or db-perf-optimized-N-4 for ENTERPRISE_PLUS."
  type        = string

  validation {
    condition     = can(regex("^db-(custom-[0-9]+-[0-9]+|perf-optimized-N-[0-9]+|f1-micro|g1-small)$", var.tier))
    error_message = "tier must look like db-custom-<vcpu>-<memory_mb>, db-perf-optimized-N-<n>, db-f1-micro or db-g1-small."
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

variable "database_version" {
  description = "PostgreSQL major version as a Cloud SQL version string (e.g. POSTGRES_16)."
  type        = string
  default     = "POSTGRES_16"

  validation {
    condition     = can(regex("^POSTGRES_[0-9]+$", var.database_version))
    error_message = "database_version must be a Cloud SQL PostgreSQL version string such as POSTGRES_16."
  }
}

variable "availability_type" {
  description = "REGIONAL (HA, synchronous standby in another zone) or ZONAL. When null the module picks REGIONAL for prod and ZONAL otherwise."
  type        = string
  default     = null

  validation {
    condition     = var.availability_type == null || contains(["REGIONAL", "ZONAL"], coalesce(var.availability_type, "ZONAL"))
    error_message = "availability_type must be REGIONAL, ZONAL or null."
  }
}

variable "disk_size_gb" {
  description = "Initial data disk size in GiB. The disk auto-grows and is never shrunk by the module."
  type        = number
  default     = 20

  validation {
    condition     = var.disk_size_gb >= 10
    error_message = "disk_size_gb must be at least 10."
  }
}

variable "disk_autoresize_limit_gb" {
  description = "Upper bound for automatic disk growth in GiB. 0 means no limit."
  type        = number
  default     = 0
}

variable "disk_type" {
  description = "Data disk type: PD_SSD or PD_HDD. HDD is only sensible for cold, low-IOPS workloads."
  type        = string
  default     = "PD_SSD"

  validation {
    condition     = contains(["PD_SSD", "PD_HDD"], var.disk_type)
    error_message = "disk_type must be PD_SSD or PD_HDD."
  }
}

variable "data_cache_enabled" {
  description = "Enable the local SSD data cache. Only applies to the ENTERPRISE_PLUS edition."
  type        = bool
  default     = true
}

###############################################################################
# PostgreSQL configuration
###############################################################################

variable "database_flags" {
  description = <<-EOT
    PostgreSQL / Cloud SQL flags as a map of flag name => value. Merged over the module's
    baseline (audit logging flags) so you can override any baseline flag except
    cloudsql.iam_authentication, which is always on.
    Example: { "max_connections" = "400", "work_mem" = "16384" }
  EOT
  type        = map(string)
  default     = {}

  validation {
    condition     = !contains(keys(var.database_flags), "cloudsql.iam_authentication")
    error_message = "cloudsql.iam_authentication is enforced by the module and cannot be overridden."
  }
}

variable "databases" {
  description = "Logical databases to create on the instance. In-database objects and GRANTs remain the DBA's responsibility."
  type        = set(string)
  default     = []

  validation {
    condition     = alltrue([for d in var.databases : can(regex("^[a-zA-Z_][a-zA-Z0-9_]{0,62}$", d))])
    error_message = "Database names must be valid unquoted PostgreSQL identifiers (letters, digits, underscore; max 63 chars)."
  }
}

variable "database_collation" {
  description = "Default collation for databases created by the module."
  type        = string
  default     = "en_US.UTF8"
}

###############################################################################
# Access - IAM identities only
###############################################################################

variable "iam_users" {
  description = "Google account emails (humans) that may log in with IAM database authentication."
  type        = set(string)
  default     = []
}

variable "iam_service_accounts" {
  description = "Service account emails (workloads on GKE / Compute Engine) that may log in with IAM database authentication."
  type        = set(string)
  default     = []

  validation {
    condition     = alltrue([for sa in var.iam_service_accounts : endswith(sa, ".gserviceaccount.com")])
    error_message = "iam_service_accounts entries must be full service account emails ending in .gserviceaccount.com."
  }
}

variable "iam_groups" {
  description = "Google Group emails whose members may log in with IAM database authentication (IAM group authentication)."
  type        = set(string)
  default     = []
}

variable "grant_project_iam_roles" {
  description = "Also grant roles/cloudsql.client and roles/cloudsql.instanceUser on the project to every principal listed above so they can actually connect. Set to false if your org manages these grants centrally."
  type        = bool
  default     = true
}

variable "require_cloud_sql_connector" {
  description = "Require clients to connect through the Cloud SQL Auth Proxy / language connectors (connector_enforcement = REQUIRED). Direct private-IP TLS connections are rejected."
  type        = bool
  default     = false
}

variable "enable_private_path_for_google_cloud_services" {
  description = "Allow Google services (e.g. BigQuery federated queries) to reach the instance over the private path."
  type        = bool
  default     = false
}

###############################################################################
# Backups, maintenance, protection
###############################################################################

variable "backup_start_time" {
  description = "Daily automated backup window start, HH:MM in UTC."
  type        = string
  default     = "02:00"

  validation {
    condition     = can(regex("^([01][0-9]|2[0-3]):[0-5][0-9]$", var.backup_start_time))
    error_message = "backup_start_time must be HH:MM (24h, UTC)."
  }
}

variable "backup_location" {
  description = "Location (region or multi-region such as \"eu\") to store backups. null = same as the instance region."
  type        = string
  default     = null
}

variable "retained_backups" {
  description = "Number of daily automated backups to retain."
  type        = number
  default     = 14

  validation {
    condition     = var.retained_backups >= 7 && var.retained_backups <= 365
    error_message = "retained_backups must be between 7 and 365."
  }
}

variable "transaction_log_retention_days" {
  description = "Days of write-ahead logs kept for point-in-time recovery (1-35)."
  type        = number
  default     = 7

  validation {
    condition     = var.transaction_log_retention_days >= 1 && var.transaction_log_retention_days <= 35
    error_message = "transaction_log_retention_days must be between 1 and 35."
  }
}

variable "maintenance_window" {
  description = "Weekly maintenance window. day: 1 (Monday) .. 7 (Sunday); hour: 0-23 UTC; update_track: canary, stable or week5."
  type = object({
    day          = optional(number, 7)
    hour         = optional(number, 3)
    update_track = optional(string, "stable")
  })
  default = {}

  validation {
    condition = (
      var.maintenance_window.day >= 1 && var.maintenance_window.day <= 7 &&
      var.maintenance_window.hour >= 0 && var.maintenance_window.hour <= 23 &&
      contains(["canary", "stable", "week5"], var.maintenance_window.update_track)
    )
    error_message = "maintenance_window.day must be 1-7, hour 0-23 and update_track one of canary, stable, week5."
  }
}

variable "deletion_protection" {
  description = "Protect the instance from deletion both in OpenTofu and in the Cloud SQL API. Leave on for anything that holds real data."
  type        = bool
  default     = true
}

variable "encryption_key_name" {
  description = "Optional Cloud KMS key (projects/.../cryptoKeys/...) for customer-managed encryption. The key must be in the instance region and the Cloud SQL service agent must have cloudkms.cryptoKeyEncrypterDecrypter on it."
  type        = string
  default     = null
}

variable "query_plans_per_minute" {
  description = "Query Insights: sampled query plans per minute (0-20)."
  type        = number
  default     = 5

  validation {
    condition     = var.query_plans_per_minute >= 0 && var.query_plans_per_minute <= 20
    error_message = "query_plans_per_minute must be between 0 and 20."
  }
}

variable "labels" {
  description = "Extra labels applied to the instance. The module always adds environment, managed-by and service labels."
  type        = map(string)
  default     = {}
}

```

### versions.tf
```hcl
terraform {
  required_version = ">= 1.6.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 5.40.0, < 8.0.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.5.0, < 4.0.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

```

### example-prod.tfvars
```hcl
# Example: a production instance with the full set of DBA-owned decisions filled in.
project_id         = "billing-prod-123456"
network_project_id = "network-host-prod-123456"
name               = "billing"
environment        = "prod"
region             = "europe-west1"

tier             = "db-perf-optimized-N-4"
edition          = "ENTERPRISE_PLUS"
database_version = "POSTGRES_16"
# availability_type is left null -> REGIONAL because environment = prod

disk_size_gb             = 200
disk_autoresize_limit_gb = 2000

databases = ["billing", "ledger"]

iam_users            = ["alice@example.com"]
iam_groups           = ["dba-team@example.com"]
iam_service_accounts = ["billing-api@billing-prod-123456.iam.gserviceaccount.com"]

database_flags = {
  "max_connections" = "500"
  "work_mem"        = "16384"
  "pgaudit.log"     = "ddl,role,write"
}

backup_location                = "eu"
retained_backups               = 30
transaction_log_retention_days = 14

maintenance_window = {
  day          = 7
  hour         = 2
  update_track = "week5"
}

labels = {
  cost-center = "finance"
}

```

### minimal.tfvars
```hcl
project_id  = "dba-sandbox-123456"
name        = "example"
environment = "dev"
tier        = "db-custom-2-7680"

```

### README.md
```markdown
# cloudsql-postgres — standard PostgreSQL module

Stands up one Cloud SQL for PostgreSQL instance the same way every time, and
leaves the decisions that are genuinely the DBA's (sizing, version, flags,
backup/maintenance schedule, who can log in) as inputs.

## What is fixed by the module (not configurable)

| Decision | Why |
|---|---|
| **Private IP only** on `apps-<environment>` (`ipv4_enabled = false`) | Apps live in those VPCs; private services access is already in place. |
| **TLS required** (`ssl_mode = ENCRYPTED_ONLY`) | No plaintext on the network. |
| **IAM database authentication always on**, and the module only creates IAM users / service accounts / groups — no password users | Everyone already has a Google identity; security audits by that identity. |
| **Automated daily backups + point-in-time recovery** | Non-negotiable for a managed database. Schedule and retention are yours. |
| **Deletion protection** (API and OpenTofu level), on by default | Flip `deletion_protection = false` only when you really mean it. |
| **Query Insights** on, with application tags and client addresses | Observability baseline. |
| **Audit flags** (`pgaudit` with `ddl,role`, `log_connections`, `log_disconnections`, `log_checkpoints`, `log_lock_waits`, `log_temp_files`, `log_min_duration_statement=1000`) | Can be overridden per flag via `database_flags`; only `cloudsql.iam_authentication` is locked. |
| **Disk auto-resize** on; `disk_size` ignored after creation | The disk only grows; a stale tfvars value will never try to shrink it. |
| **Random 4-hex suffix** on the instance name | Cloud SQL reserves deleted names for ~a week; the suffix avoids that collision. |
| **Labels** `environment`, `service`, `managed-by=opentofu` | Cost and ownership reporting. |

## What you decide

`tier`, `edition`, `database_version`, `availability_type` (defaults to
REGIONAL for prod, ZONAL elsewhere), disk size/type/limit, `database_flags`,
`databases`, `iam_users` / `iam_groups` / `iam_service_accounts`, backup window
and retention, `maintenance_window`, CMEK key, `require_cloud_sql_connector`,
extra labels.

## Minimal use

```hcl
project_id  = "my-project"
name        = "orders"
environment = "staging"
tier        = "db-custom-2-7680"
```

See `example-prod.tfvars` for a fully specified production instance.

## Access model

Each principal in `iam_users`, `iam_groups` and `iam_service_accounts` becomes a
Cloud SQL IAM user on the instance and (unless `grant_project_iam_roles = false`)
is granted `roles/cloudsql.client` and `roles/cloudsql.instanceUser` on the
project. Service accounts log in as `<sa>@<project>.iam` (the
`iam_database_users` output gives the exact role name).

Privileges *inside* PostgreSQL (`GRANT ... ON DATABASE/SCHEMA`) stay with the
DBA — the module deliberately doesn't run SQL. Newly created IAM users have
login only until you grant them something.

## Prerequisites

* `sqladmin.googleapis.com` enabled in `project_id`.
* Private services access configured on the VPC (done by the network team).
* If the VPC is in a Shared VPC host project, set `network_project_id`.
* If using `encryption_key_name`, the Cloud SQL service agent needs
  `roles/cloudkms.cryptoKeyEncrypterDecrypter` on the key.

```