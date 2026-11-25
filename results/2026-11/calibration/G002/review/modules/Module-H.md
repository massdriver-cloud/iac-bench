# Module H

## What you are doing

For each doctrine section below, record **your own grade** for this
module in review.yaml under `Module H`: 0 (no credit), 1 (partial
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
| Interface design | 1 | ⚠ check | 1 | 2 | **claude-opus-5-5:** The DBA-facing controls are appropriate (tier, edition, availability_type, backups, maintenance_window, database_flags, iam_database_users with IAM auth forced on), but `ssl_mode` exposes ALLOW_UNENCRYPTED_AND_ENCRYPTED as a security knob, and three overlapping network inputs (network_project_id, ne<br>**gpt-5.5-2026-04-23:** The inputs expose DBA-owned deployment concepts such as `environment`, `tier`, `database_version`, `databases`, and `iam_database_users` while the module fixes standard decisions like private IP and IAM authentication in `google_sql_database_instance.this`. |
| Variables and validation | 1 |  | 1 | 1 | **claude-opus-5-5:** Inputs are deliberately guarded (environment enum, backup_start_time regex, transaction_log_retention_days 1–7, the secondary_zone precondition), but `private_network_self_link` silently overrides `network_project_id`/`network_name`, an avoidable pair of inputs that can be set to conflict.<br>**gpt-5.5-2026-04-23:** Many inputs have useful validation, but realistic provider-breaking inputs such as `insights_query_string_length` and `insights_query_plans_per_minute` have no validation at all. |
| Internal logic | 2 |  | 2 | 2 | **claude-opus-5-5:** Locals derive the network path from `environment`, force the IAM-auth flag via merge, and compute the service-account username (trimsuffix) and IAM member prefix from a single type input, keeping the expressions readable.<br>**gpt-5.5-2026-04-23:** `locals` derive useful internal values such as `private_network`, merged `labels`, forced IAM auth `database_flags`, and normalized `iam_database_users` from higher-level inputs. |
| Scope | 2 |  | 2 | 2 | **claude-opus-5-5:** The module creates the private-IP-only instance with backups, PITR and Query Insights, plus `google_sql_database`, IAM `google_sql_user`, and `roles/cloudsql.instanceUser`/`client` grants that match the identity-audited access requirement without gold-plating.<br>**gpt-5.5-2026-04-23:** The module creates the Cloud SQL PostgreSQL instance, databases, IAM database users, project IAM grants, private IP configuration, backups/PITR, maintenance, and Query Insights needed for the requested standard DBA module. |
| Inline Resource Configuration vs Separate Resources | 2 |  | 2 | 2 | **claude-opus-5-5:** Databases, users and IAM bindings are separate resources (`google_sql_database`, `google_sql_user`, `google_project_iam_member`), and the settings blocks have no separate-resource alternative.<br>**gpt-5.5-2026-04-23:** The module does not mix inline and separate resources for the same provider-managed attributes; repeated items such as databases and IAM grants are separate resources. |
| Outputs | 2 |  | 2 | 2 | **claude-opus-5-5:** Outputs cover what consumers need to connect and administer (connection_name, private_ip_address, instance_name, iam_database_users usernames) without dumping every attribute.<br>**gpt-5.5-2026-04-23:** `outputs.tf` exposes the key values consumers need, including `connection_name`, `private_ip_address`, `instance_name`, `private_network`, and computed IAM database usernames. |
| Iteration: for_each vs count | 2 |  | 2 | 2 | **claude-opus-5-5:** All multiplicity uses `for_each` keyed by database name or identity email, and the `location_preference` dynamic block uses `[] : [1]` only as an on/off toggle.<br>**gpt-5.5-2026-04-23:** Multiplicity uses `for_each` on `google_sql_database.databases`, `google_sql_user.iam`, and both IAM member resources, and the module uses no `count`. |
| Data sources vs inputs | 2 |  | 2 | 2 | **claude-opus-5-5:** The module takes only the network's identity (name/project or self-link) and never asks for derived facts such as a CIDR that could mismatch the network.<br>**gpt-5.5-2026-04-23:** The module takes the VPC identity through `environment`/`network_name` or `private_network_self_link` and does not ask consumers for separately derived dependency facts such as a VPC CIDR. |
| File layout | 1 | ⚠ check | 2 | 1 | **claude-opus-5-5:** Files are split into main.tf, variables.tf, outputs.tf and versions.tf, and main.tf holds a modest set of core resources.<br>**gpt-5.5-2026-04-23:** Variables and outputs are split correctly, but `main.tf` mixes the core `google_sql_database_instance`, database resources, IAM users, and project IAM grants instead of separating clear concerns. |
| Sensitive values | 2 |  | 2 | 2 | **claude-opus-5-5:** There are no password users or secret inputs; access is purely IAM-based (`google_sql_user` with CLOUD_IAM_* types), so nothing needs to be marked sensitive.<br>**gpt-5.5-2026-04-23:** The module has no raw password, credential, or secret variables or outputs; inputs such as `iam_database_users` carry identity references rather than secrets. |
| Lifecycle meta-arguments | 2 |  | 2 | 2 | **claude-opus-5-5:** The module uses the native `deletion_protection`/`deletion_protection_enabled` rather than `prevent_destroy`, and its lifecycle block contains only a precondition, with no `ignore_changes`.<br>**gpt-5.5-2026-04-23:** The only `lifecycle` block contains a `precondition`, with no inappropriate `prevent_destroy` or `ignore_changes` usage. |
| Documentation | 2 |  | 2 | 2 | **claude-opus-5-5:** Every variable and output has an accurate description (e.g., the 0 sentinel on disk_autoresize_limit_gb), and the README correctly summarizes the baked-in decisions with usage examples.<br>**gpt-5.5-2026-04-23:** Every variable and output has a `description`, and the README accurately explains the module’s standard decisions and example usage. |
| Deprecated and escape-hatch patterns | 2 |  | 2 | 2 | **claude-opus-5-5:** The module contains no `null_resource`, `local-exec`, or deprecated resource forms.<br>**gpt-5.5-2026-04-23:** The module contains no `null_resource`, `local-exec`, remote module call, or deprecated escape-hatch pattern. |
| Anti-patterns (immediate credibility loss) | 0 |  | 0 | 0 | **claude-opus-5-5:** The `ssl_mode` validation accepts "ALLOW_UNENCRYPTED_AND_ENCRYPTED", letting a consumer silently downgrade the encryption-in-transit posture the module otherwise establishes with its ENCRYPTED_ONLY default.<br>**gpt-5.5-2026-04-23:** `variable "ssl_mode"` allows `ALLOW_UNENCRYPTED_AND_ENCRYPTED`, exposing an input that can silently violate the module’s encrypted-connection security posture. |

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
  network_name       = coalesce(var.network_name, "apps-${var.environment}")

  private_network = coalesce(
    var.private_network_self_link,
    "projects/${local.network_project_id}/global/networks/${local.network_name}"
  )

  labels = merge(
    {
      environment = var.environment
      managed_by  = "opentofu"
      service     = "postgresql"
    },
    var.labels
  )

  database_flags = merge(
    var.database_flags,
    {
      "cloudsql.iam_authentication" = "on"
    }
  )

  iam_database_users = {
    for identity, config in var.iam_database_users : identity => {
      type                = upper(config.type)
      name                = upper(config.type) == "CLOUD_IAM_SERVICE_ACCOUNT" ? trimsuffix(identity, ".gserviceaccount.com") : identity
      member              = upper(config.type) == "CLOUD_IAM_SERVICE_ACCOUNT" ? "serviceAccount:${identity}" : upper(config.type) == "CLOUD_IAM_GROUP" ? "group:${identity}" : "user:${identity}"
      grant_instance_user = config.grant_instance_user
      grant_client        = config.grant_client
    }
  }
}

resource "google_sql_database_instance" "this" {
  project          = var.project_id
  name             = var.name
  region           = var.region
  database_version = var.database_version

  deletion_protection = var.deletion_protection

  settings {
    tier                        = var.tier
    edition                     = var.edition
    availability_type           = var.availability_type
    disk_type                   = var.disk_type
    disk_size                   = var.disk_size_gb
    disk_autoresize             = true
    disk_autoresize_limit       = var.disk_autoresize_limit_gb
    deletion_protection_enabled = var.deletion_protection
    user_labels                 = local.labels

    ip_configuration {
      ipv4_enabled                                  = false
      private_network                               = local.private_network
      allocated_ip_range                            = var.allocated_ip_range
      enable_private_path_for_google_cloud_services = true
      ssl_mode                                      = var.ssl_mode
    }

    backup_configuration {
      enabled                        = true
      start_time                     = var.backup_start_time
      point_in_time_recovery_enabled = true
      transaction_log_retention_days = var.transaction_log_retention_days

      backup_retention_settings {
        retained_backups = var.retained_backups
        retention_unit   = "COUNT"
      }
    }

    maintenance_window {
      day          = var.maintenance_window.day
      hour         = var.maintenance_window.hour
      update_track = lower(var.maintenance_window.update_track)
    }

    insights_config {
      query_insights_enabled  = true
      query_string_length     = var.insights_query_string_length
      record_application_tags = true
      record_client_address   = false
      query_plans_per_minute  = var.insights_query_plans_per_minute
    }

    dynamic "database_flags" {
      for_each = local.database_flags
      content {
        name  = database_flags.key
        value = database_flags.value
      }
    }

    dynamic "location_preference" {
      for_each = var.zone == null && var.secondary_zone == null ? [] : [1]
      content {
        zone           = var.zone
        secondary_zone = var.secondary_zone
      }
    }
  }

  lifecycle {
    precondition {
      condition     = !(var.availability_type == "ZONAL" && var.secondary_zone != null)
      error_message = "secondary_zone can only be set when availability_type is REGIONAL."
    }
  }
}

resource "google_sql_database" "databases" {
  for_each = var.databases

  project   = var.project_id
  instance  = google_sql_database_instance.this.name
  name      = each.key
  charset   = each.value.charset
  collation = each.value.collation
}

resource "google_sql_user" "iam" {
  for_each = local.iam_database_users

  project  = var.project_id
  instance = google_sql_database_instance.this.name
  name     = each.value.name
  type     = each.value.type
}

resource "google_project_iam_member" "instance_user" {
  for_each = {
    for identity, user in local.iam_database_users : identity => user
    if user.grant_instance_user
  }

  project = var.project_id
  role    = "roles/cloudsql.instanceUser"
  member  = each.value.member
}

resource "google_project_iam_member" "client" {
  for_each = {
    for identity, user in local.iam_database_users : identity => user
    if user.grant_client
  }

  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = each.value.member
}

```

### outputs.tf
```hcl
output "instance_name" {
  description = "Cloud SQL instance name."
  value       = google_sql_database_instance.this.name
}

output "connection_name" {
  description = "Cloud SQL connection name in project:region:instance form."
  value       = google_sql_database_instance.this.connection_name
}

output "project_id" {
  description = "Project containing the Cloud SQL instance."
  value       = var.project_id
}

output "region" {
  description = "Region containing the Cloud SQL instance."
  value       = google_sql_database_instance.this.region
}

output "private_network" {
  description = "VPC network used for private Cloud SQL connectivity."
  value       = local.private_network
}

output "private_ip_address" {
  description = "Private IP address assigned to the instance after creation."
  value       = google_sql_database_instance.this.private_ip_address
}

output "database_version" {
  description = "Configured PostgreSQL database version."
  value       = google_sql_database_instance.this.database_version
}

output "iam_database_users" {
  description = "Cloud SQL IAM database users/groups managed by the module, keyed by Google identity email."
  value = {
    for identity, user in local.iam_database_users : identity => {
      database_username = user.name
      type              = user.type
      iam_member        = user.member
    }
  }
}

```

### variables.tf
```hcl
variable "project_id" {
  description = "Google Cloud project that owns the Cloud SQL instance and project-level IAM grants."
  type        = string
}

variable "name" {
  description = "Cloud SQL instance name. This is immutable in Google Cloud and must be unique in the project."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,96}[a-z0-9]$", var.name))
    error_message = "name must start with a lowercase letter, contain only lowercase letters, numbers and hyphens, end with a letter or number, and be at most 98 characters."
  }
}

variable "environment" {
  description = "Application environment. The default private network is apps-<environment>."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of dev, staging or prod."
  }
}

variable "region" {
  description = "Google Cloud region for the instance."
  type        = string
  default     = "us-central1"
}

variable "database_version" {
  description = "Cloud SQL PostgreSQL engine version."
  type        = string
  default     = "POSTGRES_16"

  validation {
    condition     = can(regex("^POSTGRES_[0-9]+$", var.database_version))
    error_message = "database_version must be a Cloud SQL PostgreSQL version such as POSTGRES_16."
  }
}

variable "tier" {
  description = "Cloud SQL machine tier, for example db-custom-2-8192 or db-perf-optimized-N-2."
  type        = string
  default     = "db-custom-2-8192"
}

variable "edition" {
  description = "Cloud SQL edition."
  type        = string
  default     = "ENTERPRISE"

  validation {
    condition     = contains(["ENTERPRISE", "ENTERPRISE_PLUS"], var.edition)
    error_message = "edition must be ENTERPRISE or ENTERPRISE_PLUS."
  }
}

variable "availability_type" {
  description = "Availability mode. REGIONAL provisions a highly-available standby in another zone."
  type        = string
  default     = "REGIONAL"

  validation {
    condition     = contains(["ZONAL", "REGIONAL"], var.availability_type)
    error_message = "availability_type must be ZONAL or REGIONAL."
  }
}

variable "disk_size_gb" {
  description = "Initial data disk size in GB. Autoresize is always enabled."
  type        = number
  default     = 100

  validation {
    condition     = var.disk_size_gb >= 10
    error_message = "disk_size_gb must be at least 10."
  }
}

variable "disk_type" {
  description = "Cloud SQL storage type."
  type        = string
  default     = "PD_SSD"

  validation {
    condition     = contains(["PD_SSD", "PD_HDD"], var.disk_type)
    error_message = "disk_type must be PD_SSD or PD_HDD."
  }
}

variable "disk_autoresize_limit_gb" {
  description = "Maximum size in GB to which storage can automatically grow. Set to 0 for no explicit limit."
  type        = number
  default     = 0

  validation {
    condition     = var.disk_autoresize_limit_gb >= 0
    error_message = "disk_autoresize_limit_gb must be zero or greater."
  }
}

variable "network_project_id" {
  description = "Project that owns the VPC network. Defaults to project_id."
  type        = string
  default     = null
}

variable "network_name" {
  description = "Name of the private VPC network. Defaults to apps-<environment>. Private services access must already exist."
  type        = string
  default     = null
}

variable "private_network_self_link" {
  description = "Full self-link or relative ID of the VPC network to use for private IP. Overrides network_project_id and network_name."
  type        = string
  default     = null
}

variable "allocated_ip_range" {
  description = "Optional name of the allocated private services access range for Cloud SQL private IP."
  type        = string
  default     = null
}

variable "ssl_mode" {
  description = "SSL policy for database connections. Public IPv4 is always disabled by the module."
  type        = string
  default     = "ENCRYPTED_ONLY"

  validation {
    condition     = contains(["ALLOW_UNENCRYPTED_AND_ENCRYPTED", "ENCRYPTED_ONLY", "TRUSTED_CLIENT_CERTIFICATE_REQUIRED"], var.ssl_mode)
    error_message = "ssl_mode must be ALLOW_UNENCRYPTED_AND_ENCRYPTED, ENCRYPTED_ONLY or TRUSTED_CLIENT_CERTIFICATE_REQUIRED."
  }
}

variable "deletion_protection" {
  description = "Protect the instance from accidental deletion both in OpenTofu state and in the Cloud SQL API."
  type        = bool
  default     = true
}

variable "backup_start_time" {
  description = "UTC time in HH:MM format for the daily backup window."
  type        = string
  default     = "03:00"

  validation {
    condition     = can(regex("^([01][0-9]|2[0-3]):[0-5][0-9]$", var.backup_start_time))
    error_message = "backup_start_time must be a UTC time in HH:MM format."
  }
}

variable "retained_backups" {
  description = "Number of automated backups to retain."
  type        = number
  default     = 14

  validation {
    condition     = var.retained_backups >= 1 && var.retained_backups <= 365
    error_message = "retained_backups must be between 1 and 365."
  }
}

variable "transaction_log_retention_days" {
  description = "Days of PostgreSQL transaction logs to keep for point-in-time recovery."
  type        = number
  default     = 7

  validation {
    condition     = var.transaction_log_retention_days >= 1 && var.transaction_log_retention_days <= 7
    error_message = "transaction_log_retention_days must be between 1 and 7."
  }
}

variable "maintenance_window" {
  description = "Preferred maintenance window. day is 1-7 where 1 is Monday; hour is UTC 0-23."
  type = object({
    day          = number
    hour         = number
    update_track = string
  })
  default = {
    day          = 7
    hour         = 4
    update_track = "stable"
  }

  validation {
    condition = (
      var.maintenance_window.day >= 1 && var.maintenance_window.day <= 7 &&
      var.maintenance_window.hour >= 0 && var.maintenance_window.hour <= 23 &&
      contains(["stable", "canary"], lower(var.maintenance_window.update_track))
    )
    error_message = "maintenance_window.day must be 1-7, hour must be 0-23, and update_track must be stable or canary."
  }
}

variable "zone" {
  description = "Optional preferred primary zone. Leave null to let Cloud SQL choose."
  type        = string
  default     = null
}

variable "secondary_zone" {
  description = "Optional preferred secondary zone for REGIONAL instances. Leave null to let Cloud SQL choose."
  type        = string
  default     = null
}

variable "database_flags" {
  description = "Additional Cloud SQL database flags. cloudsql.iam_authentication is always forced on by the module."
  type        = map(string)
  default     = {}
}

variable "databases" {
  description = "PostgreSQL databases to create on the instance. Keys are database names."
  type = map(object({
    charset   = optional(string, "UTF8")
    collation = optional(string, "en_US.UTF8")
  }))
  default = {}
}

variable "iam_database_users" {
  description = <<-EOT
    Google identities to create as Cloud SQL IAM database principals. Map keys are identity emails.
    Use type CLOUD_IAM_USER for user emails, CLOUD_IAM_SERVICE_ACCOUNT for service account emails, or CLOUD_IAM_GROUP for Google Groups.
    Service account database usernames are automatically converted to Cloud SQL's required form by trimming .gserviceaccount.com.
  EOT
  type = map(object({
    type                = optional(string, "CLOUD_IAM_USER")
    grant_instance_user = optional(bool, true)
    grant_client        = optional(bool, false)
  }))
  default = {}

  validation {
    condition     = alltrue([for _, user in var.iam_database_users : contains(["CLOUD_IAM_USER", "CLOUD_IAM_SERVICE_ACCOUNT", "CLOUD_IAM_GROUP"], upper(user.type))])
    error_message = "iam_database_users entries must have type CLOUD_IAM_USER, CLOUD_IAM_SERVICE_ACCOUNT or CLOUD_IAM_GROUP."
  }
}

variable "insights_query_string_length" {
  description = "Maximum query text length stored by Query Insights."
  type        = number
  default     = 1024
}

variable "insights_query_plans_per_minute" {
  description = "Maximum query plans captured per minute by Query Insights."
  type        = number
  default     = 5
}

variable "labels" {
  description = "Additional labels to apply to the Cloud SQL instance."
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
      version = ">= 5.20, < 7.0"
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
name        = "example-postgres"
environment = "dev"

```

### README.md
```markdown
# Standard Cloud SQL PostgreSQL root module

This OpenTofu root module creates a standardized Google Cloud SQL for PostgreSQL instance for the DBA team.

## Standard decisions baked in

- PostgreSQL on Cloud SQL only.
- Private IP only; public IPv4 is disabled.
- The VPC defaults to `apps-dev`, `apps-staging`, or `apps-prod` from `environment`; private services access is assumed to be pre-created by the network team.
- IAM database authentication is always enabled with the `cloudsql.iam_authentication=on` flag.
- Daily automated backups, point-in-time recovery, transaction log retention, and backup retention are enabled.
- Regional high availability, SSD storage, disk autoresize, deletion protection, Query Insights, maintenance window, and standard labels are configured by default.
- Optional Google identities can be created as Cloud SQL IAM database users/groups and granted `roles/cloudsql.instanceUser`; connector users can also receive `roles/cloudsql.client`.

## Minimal use

`minimal.tfvars` provides the smallest valid instantiation:

```hcl
project_id  = "example-project"
name        = "example-postgres"
environment = "dev"
```

Plan with:

```sh
tofu plan -var-file=minimal.tfvars
```

## Example with DBA-owned choices

```hcl
project_id  = "my-prod-project"
name        = "orders-prod"
environment = "prod"
region      = "us-central1"

tier              = "db-custom-4-16384"
database_version  = "POSTGRES_16"
disk_size_gb      = 500
retained_backups  = 30
backup_start_time = "06:00"

databases = {
  orders = {}
}

iam_database_users = {
  "orders-api@my-prod-project.iam.gserviceaccount.com" = {
    type         = "CLOUD_IAM_SERVICE_ACCOUNT"
    grant_client = true
  }
  "dba-team@example.com" = {
    type = "CLOUD_IAM_GROUP"
  }
}
```

```