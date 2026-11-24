locals {
  project_id = data.google_client_config.current.project
  region     = coalesce(var.region, data.google_client_config.current.region != "" ? data.google_client_config.current.region : null, "us-central1")

  instance_name     = endswith(var.name, "-${var.environment}") ? var.name : "${var.name}-${var.environment}"
  network_name      = "apps-${var.environment}"
  network_self_link = "projects/${local.project_id}/global/networks/${local.network_name}"

  availability_type = coalesce(var.availability_type, var.environment == "prod" ? "REGIONAL" : "ZONAL")

  env_retained_backups = {
    dev     = 7
    staging = 14
    prod    = 30
  }

  env_pitr_days = {
    dev     = 3
    staging = 7
    prod    = 7
  }

  retained_backups               = coalesce(var.backup_configuration.retained_backups, local.env_retained_backups[var.environment])
  transaction_log_retention_days = coalesce(var.backup_configuration.transaction_log_retention_days, local.env_pitr_days[var.environment])

  default_tunable_flags = {
    "pgaudit.log" = "ddl,role"
  }

  enforced_security_flags = {
    "cloudsql.iam_authentication" = "on"
    "cloudsql.enable_pgaudit"     = "on"
    "log_connections"             = "on"
    "log_disconnections"          = "on"
  }

  primary_database_flags = merge(
    local.default_tunable_flags,
    var.database_flags,
    local.enforced_security_flags,
  )

  replica_database_flags = {
    for k, r in var.read_replicas :
    k => merge(
      local.default_tunable_flags,
      var.database_flags,
      coalesce(r.database_flags, {}),
      local.enforced_security_flags,
    )
  }

  labels = merge(
    var.labels,
    {
      environment = var.environment
      managed_by  = "opentofu"
    },
  )

  # Map service account email => Cloud SQL PostgreSQL username (without '.gserviceaccount.com')
  iam_service_account_db_users = {
    for sa in var.iam_service_accounts :
    sa => trimsuffix(sa, ".gserviceaccount.com")
  }

  iam_members = merge(
    { for u in var.iam_users : "user:${u}" => "user:${u}" },
    { for sa in var.iam_service_accounts : "serviceAccount:${sa}" => "serviceAccount:${sa}" },
    { for g in var.iam_groups : "group:${g}" => "group:${g}" },
  )

  cloudsql_iam_roles = toset([
    "roles/cloudsql.client",
    "roles/cloudsql.instanceUser",
  ])

  iam_role_bindings = var.manage_iam_bindings ? {
    for pair in setproduct(keys(local.iam_members), local.cloudsql_iam_roles) :
    "${pair[0]}|${pair[1]}" => {
      member = pair[0]
      role   = pair[1]
    }
  } : {}

  managed_instance_resource_names = concat(
    ["projects/${local.project_id}/instances/${local.instance_name}"],
    [
      for k in sort(keys(var.read_replicas)) :
      "projects/${local.project_id}/instances/${local.instance_name}-replica-${k}"
    ],
  )

  iam_condition_expression = (
    length(local.managed_instance_resource_names) == 1
    ? "resource.type == \"sqladmin.googleapis.com/Instance\" && resource.name == \"${local.managed_instance_resource_names[0]}\""
    : "resource.type == \"sqladmin.googleapis.com/Instance\" && (${join(" || ", [for rn in local.managed_instance_resource_names : "resource.name == \"${rn}\""])})"
  )
}
