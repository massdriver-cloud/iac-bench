locals {
  project_id = data.google_client_config.current.project
  region     = var.region != null ? var.region : data.google_client_config.current.region

  instance_name    = "pg-${var.environment}-${var.name}"
  vpc_network_name = "apps-${var.environment}"
  vpc_network_id   = "projects/${local.project_id}/global/networks/${local.vpc_network_name}"

  # Environment-aware operational defaults (explicit DBA inputs always take precedence)
  availability_type = (
    var.availability_type != null
    ? var.availability_type
    : (var.environment == "prod" ? "REGIONAL" : "ZONAL")
  )

  deletion_protection = (
    var.deletion_protection != null
    ? var.deletion_protection
    : (var.environment == "prod")
  )

  # REGIONAL HA in Cloud SQL for PostgreSQL requires WAL archiving (PITR)
  pitr_enabled = (
    var.backup_configuration.point_in_time_recovery_enabled != null
    ? var.backup_configuration.point_in_time_recovery_enabled
    : (local.availability_type == "REGIONAL" || var.environment != "dev")
  )

  default_retained_backups = {
    dev     = 7
    staging = 14
    prod    = 30
  }

  default_transaction_log_retention_days = {
    dev     = 3
    staging = 5
    prod    = 7
  }

  retained_backups = coalesce(
    var.backup_configuration.retained_backups,
    local.default_retained_backups[var.environment]
  )

  transaction_log_retention_days = coalesce(
    var.backup_configuration.transaction_log_retention_days,
    local.default_transaction_log_retention_days[var.environment]
  )

  normalized_pgaudit_log = join(",", [
    for token in split(",", var.pgaudit_log) : lower(trimspace(token))
  ])

  # Non-negotiable security & identity-audit flags enforced across primary and replicas
  mandatory_security_flags = {
    "cloudsql.iam_authentication" = "on"
    "cloudsql.enable_pgaudit"     = "on"
    "log_connections"             = "on"
    "log_disconnections"          = "on"
    "pgaudit.log"                 = local.normalized_pgaudit_log
  }

  # Sensible DBA observability defaults (overridable via var.database_flags)
  default_dba_flags = {
    "log_checkpoints"            = "on"
    "log_lock_waits"             = "on"
    "log_min_duration_statement" = "1000"
    "log_temp_files"             = "0"
  }

  primary_database_flags = merge(
    local.default_dba_flags,
    var.database_flags,
    local.mandatory_security_flags
  )

  replica_database_flags = {
    for key, replica in var.read_replicas :
    key => merge(
      local.default_dba_flags,
      var.database_flags,
      replica.database_flags,
      local.mandatory_security_flags
    )
  }

  # Governance labels applied consistently across all managed instances
  base_labels = merge(
    var.labels,
    {
      environment = var.environment
      service     = var.name
      managed_by  = "opentofu"
    }
  )

  primary_labels = merge(local.base_labels, {
    instance_role = "primary"
  })

  # Cloud SQL PostgreSQL requires stripping '.gserviceaccount.com' from CLOUD_IAM_SERVICE_ACCOUNT user names
  service_account_sql_users = {
    for email in var.iam_service_accounts :
    email => trimsuffix(email, ".gserviceaccount.com")
  }

  iam_members = toset(concat(
    [for email in var.iam_users : "user:${email}"],
    [for email in var.iam_service_accounts : "serviceAccount:${email}"],
    [for email in var.iam_groups : "group:${email}"],
  ))
}
