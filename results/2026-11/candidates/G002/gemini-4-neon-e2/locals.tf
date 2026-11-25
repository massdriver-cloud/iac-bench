locals {
  project_id   = data.google_client_config.current.project
  region       = var.region != null ? var.region : data.google_client_config.current.region
  network_name = "apps-${var.environment}"

  env_defaults = {
    dev = {
      enterprise_tier                = "db-custom-1-3840"
      enterprise_plus_tier           = "db-perf-optimized-N-2"
      availability_type              = "ZONAL"
      disk_size                      = 20
      retained_backups               = 7
      transaction_log_retention_days = 1
      update_track                   = "canary"
      deletion_protection            = false
      retain_backups_on_delete       = false
    }
    staging = {
      enterprise_tier                = "db-custom-2-7680"
      enterprise_plus_tier           = "db-perf-optimized-N-2"
      availability_type              = "ZONAL"
      disk_size                      = 50
      retained_backups               = 14
      transaction_log_retention_days = 3
      update_track                   = "stable"
      deletion_protection            = false
      retain_backups_on_delete       = false
    }
    prod = {
      enterprise_tier                = "db-custom-2-7680"
      enterprise_plus_tier           = "db-perf-optimized-N-4"
      availability_type              = "REGIONAL"
      disk_size                      = 100
      retained_backups               = 30
      transaction_log_retention_days = 7
      update_track                   = "stable"
      deletion_protection            = true
      retain_backups_on_delete       = true
    }
  }

  env = local.env_defaults[var.environment]

  default_tier = var.edition == "ENTERPRISE_PLUS" ? local.env.enterprise_plus_tier : local.env.enterprise_tier

  tier                           = var.tier != null ? var.tier : local.default_tier
  availability_type              = var.availability_type != null ? var.availability_type : local.env.availability_type
  disk_size                      = var.disk_size != null ? var.disk_size : local.env.disk_size
  retained_backups               = var.backup_configuration.retained_backups != null ? var.backup_configuration.retained_backups : local.env.retained_backups
  transaction_log_retention_days = var.backup_configuration.transaction_log_retention_days != null ? var.backup_configuration.transaction_log_retention_days : local.env.transaction_log_retention_days
  maintenance_update_track       = var.maintenance_window.update_track != null ? var.maintenance_window.update_track : local.env.update_track
  deletion_protection            = var.deletion_protection != null ? var.deletion_protection : local.env.deletion_protection
  retain_backups_on_delete       = var.retain_backups_on_delete != null ? var.retain_backups_on_delete : local.env.retain_backups_on_delete

  max_transaction_log_retention_days = var.edition == "ENTERPRISE_PLUS" ? 35 : 7

  # Standardized operational & auditing defaults (tunable by DBAs within guardrails)
  default_database_flags = {
    "pgaudit.log"                = "ddl,role,write"
    "log_checkpoints"            = "on"
    "log_lock_waits"             = "on"
    "log_temp_files"             = "0"
    "log_min_duration_statement" = "1000"
  }

  # Mandatory security & auditing flags (enforced everywhere, cannot be disabled)
  mandatory_database_flags = {
    "cloudsql.iam_authentication" = "on"
    "cloudsql.enable_pgaudit"     = "on"
    "log_connections"             = "on"
    "log_disconnections"          = "on"
  }

  effective_database_flags = merge(
    local.default_database_flags,
    var.database_flags,
    local.mandatory_database_flags,
  )

  standard_labels = {
    managed_by  = "opentofu"
    environment = var.environment
    engine      = "postgresql"
  }

  primary_labels = merge(
    var.labels,
    local.standard_labels,
    {
      role = "primary"
    },
  )

  replica_configs = {
    for k, r in var.read_replicas : k => {
      name                  = "${var.name}-${k}"
      region                = r.region != null ? r.region : local.region
      zone                  = r.zone
      tier                  = r.tier != null ? r.tier : local.tier
      availability_type     = r.availability_type
      disk_type             = r.disk_type != null ? r.disk_type : var.disk_type
      disk_autoresize_limit = r.disk_autoresize_limit != null ? r.disk_autoresize_limit : var.disk_autoresize_limit
      encryption_key_name   = r.encryption_key_name != null ? r.encryption_key_name : (r.region == null || r.region == local.region ? var.encryption_key_name : null)
      deletion_protection   = r.deletion_protection != null ? r.deletion_protection : local.deletion_protection
      database_flags = merge(
        local.effective_database_flags,
        r.database_flags,
        local.mandatory_database_flags,
      )
      labels = merge(
        var.labels,
        r.labels,
        local.standard_labels,
        {
          role = "read-replica"
        },
      )
    }
  }

  # Unified Google identities for Cloud SQL IAM database authentication
  iam_identities = merge(
    {
      for u in var.iam_users : "user:${u}" => {
        sql_username = u
        sql_type     = "CLOUD_IAM_USER"
        iam_member   = "user:${u}"
      }
    },
    {
      for sa in var.iam_service_accounts : "serviceAccount:${sa}" => {
        sql_username = trimsuffix(sa, ".gserviceaccount.com")
        sql_type     = "CLOUD_IAM_SERVICE_ACCOUNT"
        iam_member   = "serviceAccount:${sa}"
      }
    },
    {
      for g in var.iam_groups : "group:${g}" => {
        sql_username = g
        sql_type     = "CLOUD_IAM_GROUP"
        iam_member   = "group:${g}"
      }
    },
  )

  # Roles needed for IAM database authentication + Cloud SQL Auth Proxy / Language Connectors
  iam_roles = [
    "roles/cloudsql.instanceUser",
    "roles/cloudsql.client",
  ]

  iam_role_bindings = var.grant_iam_roles ? merge([
    for id_key, id_val in local.iam_identities : {
      for role in local.iam_roles : "${id_key}|${role}" => {
        member = id_val.iam_member
        role   = role
      }
    }
  ]...) : {}
}
