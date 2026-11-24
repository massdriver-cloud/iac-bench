locals {
  project_id    = data.google_client_config.current.project
  region        = try(coalesce(var.region, data.google_client_config.current.region), "")
  network_name  = "apps-${var.environment}"
  instance_name = "${var.name}-${var.environment}"

  replica_instance_names = {
    for key in sort(keys(var.read_replicas)) :
    key => "${local.instance_name}-replica-${key}"
  }

  all_instance_names = concat(
    [local.instance_name],
    [for key in sort(keys(var.read_replicas)) : local.replica_instance_names[key]]
  )

  env_retained_backups = {
    dev     = 7
    staging = 14
    prod    = 30
  }

  env_wal_retention_days = {
    dev     = 3
    staging = 7
    prod    = 7
  }

  availability_type              = coalesce(var.availability_type, var.environment == "prod" ? "REGIONAL" : "ZONAL")
  deletion_protection            = coalesce(var.deletion_protection, var.environment == "prod")
  retained_backups               = coalesce(var.backup_configuration.retained_backups, local.env_retained_backups[var.environment])
  transaction_log_retention_days = coalesce(var.backup_configuration.transaction_log_retention_days, local.env_wal_retention_days[var.environment])
  point_in_time_recovery_enabled = coalesce(var.backup_configuration.point_in_time_recovery_enabled, true)

  default_database_flags = {
    "log_checkpoints"            = "on"
    "log_lock_waits"             = "on"
    "log_min_duration_statement" = "1000"
    "log_temp_files"             = "0"
    "pgaudit.log"                = "all"
  }

  enforced_database_flags = {
    "cloudsql.enable_pgaudit"     = "on"
    "cloudsql.iam_authentication" = "on"
    "log_connections"             = "on"
    "log_disconnections"          = "on"
  }

  effective_database_flags = merge(
    local.default_database_flags,
    var.database_flags,
    local.enforced_database_flags,
  )

  replica_database_flags = {
    for key, replica in var.read_replicas :
    key => merge(
      local.effective_database_flags,
      replica.database_flags,
      local.enforced_database_flags,
    )
  }

  standard_labels = {
    environment = var.environment
    instance    = var.name
    managed_by  = "opentofu"
  }

  effective_labels = merge(var.labels, local.standard_labels)

  user_deletion_policy = var.abandon_users_on_destroy ? "ABANDON" : null

  iam_members = toset(concat(
    [for email in sort(tolist(var.iam_users)) : "user:${email}"],
    [for sa in sort(tolist(var.iam_service_accounts)) : "serviceAccount:${sa}"],
    [for group in sort(tolist(var.iam_groups)) : "group:${group}"],
  ))

  iam_roles = [
    "roles/cloudsql.client",
    "roles/cloudsql.instanceUser",
  ]

  iam_role_bindings = var.grant_iam_roles ? {
    for pair in setproduct(local.iam_roles, local.iam_members) :
    "${pair[0]}::${pair[1]}" => {
      role   = pair[0]
      member = pair[1]
    }
  } : {}

  iam_instance_condition_expression = (
    length(local.all_instance_names) == 1
    ? "resource.type == \"sqladmin.googleapis.com/Instance\" && resource.name == \"projects/${local.project_id}/instances/${local.instance_name}\""
    : "resource.type == \"sqladmin.googleapis.com/Instance\" && (${join(" || ", [for inst in local.all_instance_names : "resource.name == \"projects/${local.project_id}/instances/${inst}\""])})"
  )
}
