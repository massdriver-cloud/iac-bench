locals {
  project_id = data.google_client_config.current.project
  region     = coalesce(var.region, data.google_client_config.current.region)

  # Enforce deterministic environment-scoped naming in the shared GCP project.
  instance_name    = endswith(var.name, "-${var.environment}") ? var.name : "${var.name}-${var.environment}"
  vpc_network_name = "apps-${var.environment}"

  # Environment-aware defaults that DBAs can still consciously override where appropriate.
  availability_type      = coalesce(var.availability_type, var.environment == "prod" ? "REGIONAL" : "ZONAL")
  deletion_protection    = var.deletion_protection != null ? var.deletion_protection : (var.environment != "dev")
  backup_retention_count = coalesce(var.backup_retention_count, var.environment == "prod" ? 30 : (var.environment == "staging" ? 14 : 7))
  pitr_retention_days    = coalesce(var.pitr_retention_days, 7)

  # Sensible DBA defaults that can be overridden in var.database_flags.
  default_database_flags = {
    log_min_duration_statement = "1000"
  }

  # Platform-enforced IAM authentication and security audit logging flags.
  # Merged last so instance-by-instance tuning cannot disable security standards.
  mandatory_database_flags = {
    "cloudsql.enable_pgaudit"     = "on"
    "cloudsql.iam_authentication" = "on"
    "log_checkpoints"             = "on"
    "log_connections"             = "on"
    "log_disconnections"          = "on"
    "log_lock_waits"              = "on"
    "pgaudit.log"                 = var.pgaudit_log
  }

  primary_database_flags = merge(
    local.default_database_flags,
    var.database_flags,
    local.mandatory_database_flags,
  )

  standard_labels = {
    environment = var.environment
    engine      = "postgresql"
    managed_by  = "opentofu"
    workload    = var.name
  }

  primary_labels = merge(var.labels, local.standard_labels, {
    instance_role = "primary"
  })

  # Normalize service accounts for PostgreSQL IAM usernames (must omit .gserviceaccount.com)
  # while retaining full emails for GCP IAM member bindings.
  iam_service_accounts = {
    for sa in var.iam_service_accounts : sa => {
      full_email  = endswith(sa, ".gserviceaccount.com") ? sa : "${sa}.gserviceaccount.com"
      sql_user_id = trimsuffix(sa, ".gserviceaccount.com")
    }
  }

  # All Cloud SQL instance resource paths (primary + read replicas) for scoped IAM conditions.
  instance_resource_names = concat(
    ["projects/${local.project_id}/instances/${local.instance_name}"],
    [for k in sort(keys(var.read_replicas)) : "projects/${local.project_id}/instances/${local.instance_name}-rr-${k}"]
  )

  iam_instance_name_clauses = join(" || ", [
    for name in local.instance_resource_names : "resource.name == \"${name}\""
  ])

  iam_instance_condition_expression = "resource.type == \"sqladmin.googleapis.com/Instance\" && (${local.iam_instance_name_clauses})"
}
