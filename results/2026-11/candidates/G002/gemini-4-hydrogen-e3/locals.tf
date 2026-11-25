locals {
  vpc_network_by_env = {
    dev     = "apps-dev"
    staging = "apps-staging"
    prod    = "apps-prod"
  }

  vpc_network_name = local.vpc_network_by_env[var.environment]
  instance_name    = "${var.name}-${var.environment}"
  is_prod          = var.environment == "prod"

  tier                     = coalesce(var.tier, local.is_prod ? "db-custom-2-8192" : "db-custom-1-3840")
  availability_type        = coalesce(var.availability_type, local.is_prod ? "REGIONAL" : "ZONAL")
  disk_size                = coalesce(var.disk_size, local.is_prod ? 100 : 20)
  deletion_protection      = coalesce(var.deletion_protection, var.environment != "dev")
  retained_backups         = coalesce(var.retained_backups, local.is_prod ? 14 : 7)
  maintenance_update_track = coalesce(var.maintenance_window_update_track, var.environment == "dev" ? "canary" : "stable")

  labels = merge(
    var.labels,
    {
      environment     = var.environment
      managed_by      = "opentofu"
      database_engine = "postgresql"
    }
  )

  # Recommended operational defaults that DBAs may tune via var.database_flags.
  default_database_flags = {
    log_min_duration_statement = "1000"
  }

  # Baseline security, IAM authentication, and audit flags enforced on every instance.
  enforced_database_flags = {
    "cloudsql.iam_authentication" = "on"
    "cloudsql.enable_pgaudit"     = "on"
    "pgaudit.log"                 = var.pgaudit_log
    "log_connections"             = "on"
    "log_disconnections"          = "on"
    "log_checkpoints"             = "on"
    "log_lock_waits"              = "on"
    "log_temp_files"              = "0"
  }

  effective_database_flags = merge(
    local.default_database_flags,
    var.database_flags,
    local.enforced_database_flags,
  )

  iam_principals = merge(
    {
      for u in var.iam_users : "user:${u}" => {
        sql_name   = u
        sql_type   = "CLOUD_IAM_USER"
        iam_member = "user:${u}"
      }
    },
    {
      for sa in var.iam_service_accounts : "sa:${sa}" => {
        sql_name   = trimsuffix(sa, ".gserviceaccount.com")
        sql_type   = "CLOUD_IAM_SERVICE_ACCOUNT"
        iam_member = "serviceAccount:${endswith(sa, ".gserviceaccount.com") ? sa : "${sa}.gserviceaccount.com"}"
      }
    },
    {
      for g in var.iam_groups : "group:${g}" => {
        sql_name   = g
        sql_type   = "CLOUD_IAM_GROUP"
        iam_member = "group:${g}"
      }
    },
  )

  cloudsql_iam_roles = [
    "roles/cloudsql.instanceUser",
    "roles/cloudsql.client",
  ]

  iam_role_bindings = var.manage_iam_bindings ? {
    for pair in flatten([
      for k, principal in local.iam_principals : [
        for role in local.cloudsql_iam_roles : {
          key    = "${k}|${role}"
          member = principal.iam_member
          role   = role
        }
      ]
    ]) : pair.key => pair
  } : {}

  scoped_instance_resource_names = concat(
    ["projects/${data.google_client_config.current.project}/instances/${local.instance_name}"],
    [for k in keys(var.read_replicas) : "projects/${data.google_client_config.current.project}/instances/${local.instance_name}-${k}"]
  )

  iam_condition_expression = "resource.type == \"sqladmin.googleapis.com/Instance\" && (${join(" || ", [for r in local.scoped_instance_resource_names : "resource.name == \"${r}\""])})"
}
