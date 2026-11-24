locals {
  project_id       = data.google_client_config.current.project
  region           = coalesce(var.region, data.google_client_config.current.region)
  vpc_network_name = "apps-${var.environment}"

  environment_defaults = {
    dev = {
      availability_type              = "ZONAL"
      deletion_protection            = false
      retained_backups               = 7
      transaction_log_retention_days = 3
      maintenance_update_track       = "canary"
    }
    staging = {
      availability_type              = "ZONAL"
      deletion_protection            = false
      retained_backups               = 14
      transaction_log_retention_days = 7
      maintenance_update_track       = "stable"
    }
    prod = {
      availability_type              = "REGIONAL"
      deletion_protection            = true
      retained_backups               = 30
      transaction_log_retention_days = 7
      maintenance_update_track       = "stable"
    }
  }

  env_defaults = local.environment_defaults[var.environment]

  availability_type              = coalesce(var.availability_type, local.env_defaults.availability_type)
  deletion_protection            = var.deletion_protection != null ? var.deletion_protection : local.env_defaults.deletion_protection
  retained_backups               = coalesce(var.retained_backups, local.env_defaults.retained_backups)
  transaction_log_retention_days = coalesce(var.transaction_log_retention_days, local.env_defaults.transaction_log_retention_days)
  maintenance_update_track       = coalesce(var.maintenance_window.update_track, local.env_defaults.maintenance_update_track)

  # Sensible operational defaults that DBAs can tune via var.database_flags.
  default_operational_flags = {
    "pgaudit.log"                = "ddl,role"
    "log_checkpoints"            = "on"
    "log_lock_waits"             = "on"
    "log_min_duration_statement" = "1000"
    "log_temp_files"             = "0"
  }

  # Organization-wide security and audit flags that cannot be disabled.
  mandatory_security_flags = {
    "cloudsql.iam_authentication" = "on"
    "cloudsql.enable_pgaudit"     = "on"
    "log_connections"             = "on"
    "log_disconnections"          = "on"
  }

  primary_database_flags = merge(
    local.default_operational_flags,
    var.database_flags,
    local.mandatory_security_flags,
  )

  standard_labels = {
    managed-by  = "opentofu"
    environment = var.environment
    engine      = "postgresql"
    network     = local.vpc_network_name
  }

  primary_labels = merge(
    var.labels,
    local.standard_labels,
    {
      role = "primary"
    },
  )

  # Cloud SQL for PostgreSQL requires stripping the .gserviceaccount.com suffix
  # from CLOUD_IAM_SERVICE_ACCOUNT usernames.
  iam_service_account_usernames = {
    for sa in var.iam_service_accounts : sa => trimsuffix(sa, ".gserviceaccount.com")
  }

  iam_principals = concat(
    [for u in var.iam_users : "user:${u}"],
    [for sa in var.iam_service_accounts : "serviceAccount:${sa}"],
    [for g in var.iam_groups : "group:${g}"],
  )

  project_iam_roles = [
    "roles/cloudsql.instanceUser",
    "roles/cloudsql.client",
  ]

  project_iam_bindings = var.grant_project_iam_roles ? {
    for pair in setproduct(local.iam_principals, local.project_iam_roles) :
    "${pair[0]}|${pair[1]}" => {
      member = pair[0]
      role   = pair[1]
    }
  } : {}
}
