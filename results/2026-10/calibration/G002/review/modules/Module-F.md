# Module F

## What you are doing

For each doctrine section below, record **your own grade** for this
module in review.yaml under `Module F`: 0 (no credit), 1 (partial
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
| Interface design |  | blank | 2 | 2 | **claude-opus-5-5:** The inputs fit a specialist DBA audience: the module exposes `tier`, `database_flags`, `high_availability`, `backup`, `maintenance_day`/`maintenance_hour` and `kms_key_name`, and it fixes the shared posture (`ipv4_enabled = false`, IAM-only auth, connection logging) so no input can override it.<br>**gpt-5.5-2026-04-23:** The module exposes DBA-owned concepts such as `tier`, `high_availability`, `database_flags`, `backup`, and IAM identity sets while hardcoding standard posture choices like IAM authentication flags and private-only IPv4 in `google_sql_database_instance.this`. |
| Variables and validation |  | blank | 2 | 1 | **claude-opus-5-5:** The mistakes a consumer would realistically make are guarded: `database_version`, `ssl_mode`, `maintenance_day`/`maintenance_hour`, the `backup.start_time` format, `backup.log_retention_days` (1–7) and the `iam_service_accounts` email suffix all have validations with explanatory messages, and no con<br>**gpt-5.5-2026-04-23:** The module has deliberate validations for `database_version`, `ssl_mode`, maintenance windows, backup time, and service account emails, but routine breakage-prone numeric inputs such as `disk_size_gb`, `disk_autoresize_limit_gb`, and `backup.retained_backups` have no validation. |
| Internal logic |  | blank | 2 | 2 | **claude-opus-5-5:** `local.login_grants` builds the member×role map with `setproduct` in a readable way, and `private_network` is derived from the network name plus `data.google_client_config.current.project` rather than requiring another input.<br>**gpt-5.5-2026-04-23:** `locals` derive `labels`, `login_members`, and `login_grants` from higher-level inputs instead of requiring callers to enumerate every IAM grant. |
| Scope |  | blank | 2 | 2 | **claude-opus-5-5:** The module creates the instance, `google_sql_database`, IAM database users and instance-conditioned `google_project_iam_member` login grants, with private IP, backups and optional CMEK — proportionate to the brief without gold-plating.<br>**gpt-5.5-2026-04-23:** The module creates the Cloud SQL PostgreSQL instance, databases, IAM database users, project IAM login/client grants, private IP configuration, backups, maintenance, query insights, labels, and optional CMEK support needed for the requested standard Cloud SQL module. |
| Inline Resource Configuration vs Separate Resources |  | blank | 2 | 2 | **claude-opus-5-5:** Databases and users are separate `google_sql_database` and `google_sql_user` resources, and the dynamic `database_flags` block is the provider's only form for flags.<br>**gpt-5.5-2026-04-23:** The module does not use competing inline and separate resource styles for the same configurable child resources; repeated items such as databases and IAM grants are modeled as separate resources. |
| Outputs |  | blank | 2 | 2 | **claude-opus-5-5:** The outputs `connection_name`, `private_ip_address` and `server_ca_cert` cover what connectors and clients need, without dumping every attribute.<br>**gpt-5.5-2026-04-23:** The outputs expose the main values consumers need to connect to and verify the instance: `connection_name`, `private_ip_address`, and `server_ca_cert`. |
| Iteration: for_each vs count |  | blank | 2 | 2 | **claude-opus-5-5:** `google_sql_database`, both `google_sql_user` resources and `google_project_iam_member.sql_login` all use `for_each` over sets or maps keyed by stable values.<br>**gpt-5.5-2026-04-23:** Multiplicity is handled with `for_each` on `google_sql_database.this`, `google_sql_user.iam`, `google_sql_user.iam_service_account`, and `google_project_iam_member.sql_login`, with no index-based `count`. |
| Data sources vs inputs |  | blank | 2 | 2 | **claude-opus-5-5:** The module takes only the network name and resolves the project via `data.google_client_config.current` instead of asking for redundant facts.<br>**gpt-5.5-2026-04-23:** The module takes only the VPC identity as `var.network` and does not ask callers for separately derivable VPC facts such as CIDR ranges. |
| File layout |  | blank | 2 | 1 | **claude-opus-5-5:** Resources, variables, outputs, provider and version constraints are split across `main.tf`, `variables.tf`, `outputs.tf`, `providers.tf` and `versions.tf`, and `main.tf` stays small.<br>**gpt-5.5-2026-04-23:** Variables and outputs are separated into `variables.tf` and `outputs.tf`, but `main.tf` combines distinct concerns including the SQL instance, databases, users, and IAM grants. |
| Sensitive values |  | blank | 2 | 2 | **claude-opus-5-5:** Authentication is IAM-only with no password inputs or `google_sql_user` passwords, and the `server_ca_cert` output is marked `sensitive = true`.<br>**gpt-5.5-2026-04-23:** The module accepts no database passwords or raw secrets, and the only potentially confidential output, `server_ca_cert`, is marked `sensitive = true`. |
| Lifecycle meta-arguments |  | blank | 2 | 2 | **claude-opus-5-5:** There are no `lifecycle` blocks; protection uses the native `deletion_protection` attribute instead of `prevent_destroy`.<br>**gpt-5.5-2026-04-23:** No `lifecycle`, `prevent_destroy`, or `ignore_changes` meta-arguments are used, while native `deletion_protection` is configured on the Cloud SQL instance. |
| Documentation |  | blank | 2 | 2 | **claude-opus-5-5:** Every variable and output has a description, and comments accurately explain non-obvious choices such as the `.gserviceaccount.com` trimming, the ABANDON `deletion_policy`, and why both IAM roles are needed.<br>**gpt-5.5-2026-04-23:** Every variable and output has a `description`, and comments explain non-obvious choices such as IAM-only authentication and the IAM roles needed for Cloud SQL login. |
| Deprecated and escape-hatch patterns |  | blank | 2 | 2 | **claude-opus-5-5:** The module contains no `null_resource`, no `local-exec` and no deprecated resource forms.<br>**gpt-5.5-2026-04-23:** The module uses first-class Google provider resources and contains no `null_resource`, `local-exec`, or apparent deprecated resource form. |
| Anti-patterns (immediate credibility loss) |  | blank | 2 | 2 | **claude-opus-5-5:** The required flags are merged after `var.database_flags`, so consumers cannot disable IAM auth or connection logging, and no remote modules are called.<br>**gpt-5.5-2026-04-23:** The module authors the resources directly with `google_sql_database_instance`, `google_sql_database`, `google_sql_user`, and `google_project_iam_member` rather than calling a remote module or hiding errors by omitting the requested resources. |

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
  labels = merge(var.labels, { managed-by = "opentofu" })

  login_members = concat(
    [for u in var.iam_users : "user:${u}"],
    [for sa in var.iam_service_accounts : "serviceAccount:${sa}"],
  )
  login_grants = {
    for pair in setproduct(local.login_members, ["roles/cloudsql.instanceUser", "roles/cloudsql.client"]) :
    "${pair[1]} ${pair[0]}" => { member = pair[0], role = pair[1] }
  }
}

# Authentication is IAM-only: no built-in passwords are created or accepted.
# Identity login and connection logging are applied after the flags input, so
# no input can turn them off.
data "google_client_config" "current" {}

resource "google_sql_database_instance" "this" {
  name                = var.instance_name
  database_version    = var.database_version
  deletion_protection = var.deletion_protection
  # Customer-managed key, if policy requires one; it can only be set at creation.
  encryption_key_name = var.kms_key_name

  settings {
    tier                  = var.tier
    edition               = "ENTERPRISE"
    availability_type     = var.high_availability ? "REGIONAL" : "ZONAL"
    disk_type             = "PD_SSD"
    disk_size             = var.disk_size_gb
    disk_autoresize       = true
    disk_autoresize_limit = var.disk_autoresize_limit_gb
    # Cloud SQL instances do not inherit the provider's default_labels.
    user_labels = local.labels
    # Backups outlive the instance, so retiring one never loses its history.
    retain_backups_on_delete = true

    ip_configuration {
      ipv4_enabled    = false
      private_network = "projects/${data.google_client_config.current.project}/global/networks/${var.network}"
      ssl_mode        = var.ssl_mode
    }

    backup_configuration {
      enabled                        = var.backup.enabled
      point_in_time_recovery_enabled = var.backup.enabled
      start_time                     = var.backup.start_time
      transaction_log_retention_days = var.backup.log_retention_days

      backup_retention_settings {
        retained_backups = var.backup.retained_backups
      }
    }

    maintenance_window {
      day  = var.maintenance_day
      hour = var.maintenance_hour
    }

    insights_config {
      query_insights_enabled = true
    }

    dynamic "database_flags" {
      for_each = merge(var.database_flags, {
        "cloudsql.iam_authentication" = "on"
        log_connections               = "on"
        log_disconnections            = "on"
      })
      content {
        name  = database_flags.key
        value = database_flags.value
      }
    }
  }
}

resource "google_sql_database" "this" {
  for_each = var.databases

  name     = each.value
  instance = google_sql_database_instance.this.name
  # Removing a name from var.databases keeps the data while the instance is
  # protected; turn deletion protection off to drop it for real.
  deletion_policy = var.deletion_protection ? "ABANDON" : "DELETE"
}

# People log in as CLOUD_IAM_USER, workloads as CLOUD_IAM_SERVICE_ACCOUNT
# (Cloud SQL names a service-account user by its email without the
# .gserviceaccount.com suffix).
resource "google_sql_user" "iam" {
  for_each = var.iam_users

  name     = each.value
  instance = google_sql_database_instance.this.name
  type     = "CLOUD_IAM_USER"
}

resource "google_sql_user" "iam_service_account" {
  for_each = var.iam_service_accounts

  name     = trimsuffix(each.value, ".gserviceaccount.com")
  instance = google_sql_database_instance.this.name
  type     = "CLOUD_IAM_SERVICE_ACCOUNT"
}

# A database user alone cannot log in: IAM login needs instanceUser, and the
# Cloud SQL connectors need client. Both are scoped to this instance.
resource "google_project_iam_member" "sql_login" {
  for_each = local.login_grants

  project = google_sql_database_instance.this.project
  role    = each.value.role
  member  = each.value.member

  condition {
    title      = "cloudsql-${google_sql_database_instance.this.name}"
    expression = "resource.name == 'projects/${google_sql_database_instance.this.project}/instances/${google_sql_database_instance.this.name}'"
  }
}

```

### outputs.tf
```hcl
output "connection_name" {
  description = "Connection name for the Cloud SQL connectors and Auth Proxy."
  value       = google_sql_database_instance.this.connection_name
}

output "private_ip_address" {
  description = "Private IP address of the instance."
  value       = google_sql_database_instance.this.private_ip_address
}

output "server_ca_cert" {
  description = "Server CA certificate clients use to verify the instance."
  value       = google_sql_database_instance.this.server_ca_cert[0].cert
  sensitive   = true
}

```

### providers.tf
```hcl
provider "google" {
  region = var.region
}

```

### variables.tf
```hcl
variable "instance_name" {
  description = "Instance name, unique within the project."
  type        = string
}

variable "network" {
  description = "Name of the VPC network in this project for private IP. Private services access must already be configured on it."
  type        = string
}

variable "database_version" {
  description = "Cloud SQL PostgreSQL version identifier."
  type        = string
  default     = "POSTGRES_17"

  validation {
    condition     = contains(["POSTGRES_15", "POSTGRES_16", "POSTGRES_17"], var.database_version)
    error_message = "database_version must be POSTGRES_15, POSTGRES_16, or POSTGRES_17."
  }
}

variable "tier" {
  description = "Machine tier."
  type        = string
  default     = "db-custom-4-15360"
}

variable "high_availability" {
  description = "Run a regional instance with a standby in another zone and automatic failover."
  type        = bool
  default     = false
}

variable "disk_size_gb" {
  description = "Initial disk size in GB."
  type        = number
  default     = 50
}

variable "disk_autoresize_limit_gb" {
  description = "Upper bound for automatic disk growth in GB. 0 means no limit."
  type        = number
  default     = 0
}

variable "ssl_mode" {
  description = "Connection encryption: ENCRYPTED_ONLY, or TRUSTED_CLIENT_CERTIFICATE_REQUIRED to also require client certificates."
  type        = string
  default     = "TRUSTED_CLIENT_CERTIFICATE_REQUIRED"

  validation {
    condition     = contains(["ENCRYPTED_ONLY", "TRUSTED_CLIENT_CERTIFICATE_REQUIRED"], var.ssl_mode)
    error_message = "ssl_mode must be ENCRYPTED_ONLY or TRUSTED_CLIENT_CERTIFICATE_REQUIRED."
  }
}

variable "database_flags" {
  description = "PostgreSQL flags as name => value."
  type        = map(string)
  default     = {}
}

variable "maintenance_day" {
  description = "Maintenance day, 1 = Monday .. 7 = Sunday."
  type        = number
  default     = 6

  validation {
    condition     = contains([1, 2, 3, 4, 5, 6, 7], var.maintenance_day)
    error_message = "maintenance_day must be 1 (Monday) through 7 (Sunday)."
  }
}

variable "maintenance_hour" {
  description = "Maintenance hour, 0-23 UTC."
  type        = number
  default     = 4

  validation {
    condition     = var.maintenance_hour >= 0 && var.maintenance_hour <= 23 && floor(var.maintenance_hour) == var.maintenance_hour
    error_message = "maintenance_hour must be a whole hour from 0 to 23 (UTC)."
  }
}

variable "backup" {
  description = "Backup policy. enabled = false turns off automated backups and point-in-time recovery."
  type = object({
    enabled            = optional(bool, true)
    start_time         = optional(string, "03:00")
    retained_backups   = optional(number, 14)
    log_retention_days = optional(number, 7)
  })
  default = {}

  validation {
    condition     = can(regex("^([01][0-9]|2[0-3]):[0-5][0-9]$", var.backup.start_time))
    error_message = "backup.start_time must be HH:MM (24-hour, UTC)."
  }

  validation {
    condition     = var.backup.log_retention_days >= 1 && var.backup.log_retention_days <= 7
    error_message = "backup.log_retention_days must be 1-7 on the Enterprise edition."
  }
}

variable "deletion_protection" {
  description = "Guard the instance against destroy. Set false only to retire it."
  type        = bool
  default     = true
}

variable "databases" {
  description = "Databases to create on the instance. While deletion protection is on, removing one leaves its data in place."
  type        = set(string)
  default     = []
}

variable "iam_users" {
  description = "Email addresses of people granted database login through IAM authentication."
  type        = set(string)
  default     = []
}

variable "iam_service_accounts" {
  description = "Workload service-account emails granted database login through IAM authentication."
  type        = set(string)
  default     = []

  validation {
    condition     = alltrue([for sa in var.iam_service_accounts : endswith(sa, ".gserviceaccount.com")])
    error_message = "iam_service_accounts takes service-account emails ending in .gserviceaccount.com; put people in iam_users."
  }
}

variable "labels" {
  description = "Labels to apply to the instance."
  type        = map(string)
  default     = {}
}

variable "region" {
  description = "GCP region the instance runs in."
  type        = string
  default     = "us-central1"
}

variable "kms_key_name" {
  description = "Cloud KMS key (projects/.../cryptoKeys/...) for customer-managed encryption. Only settable when the instance is created; null uses Google-managed keys."
  type        = string
  default     = null
}

```

### versions.tf
```hcl
terraform {
  required_version = ">= 1.6.0, < 2.0.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 7.0"
    }
  }
}

```

### minimal.tfvars
```hcl
instance_name = "billing-db"
network       = "apps-dev"

```