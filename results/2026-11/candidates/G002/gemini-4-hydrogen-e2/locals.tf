locals {
  instance_name = "${var.name}-${var.environment}"
  vpc_name      = "apps-${var.environment}"

  env_defaults = {
    dev = {
      tier                           = "db-custom-1-3840"
      tier_enterprise_plus           = "db-perf-optimized-N-2"
      availability_type              = "ZONAL"
      disk_size                      = 20
      retained_backups               = 7
      transaction_log_retention_days = 3
      update_track                   = "canary"
    }
    staging = {
      tier                           = "db-custom-2-8192"
      tier_enterprise_plus           = "db-perf-optimized-N-4"
      availability_type              = "ZONAL"
      disk_size                      = 50
      retained_backups               = 14
      transaction_log_retention_days = 7
      update_track                   = "stable"
    }
    prod = {
      tier                           = "db-custom-4-16384"
      tier_enterprise_plus           = "db-perf-optimized-N-8"
      availability_type              = "REGIONAL"
      disk_size                      = 100
      retained_backups               = 30
      transaction_log_retention_days = 7
      update_track                   = "stable"
    }
  }

  defaults = local.env_defaults[var.environment]

  default_tier      = var.edition == "ENTERPRISE_PLUS" ? local.defaults.tier_enterprise_plus : local.defaults.tier
  tier              = coalesce(var.tier, local.default_tier)
  availability_type = coalesce(var.availability_type, local.defaults.availability_type)
  disk_size         = coalesce(var.disk_size, local.defaults.disk_size)

  backup_start_time              = coalesce(var.backup_configuration.start_time, "03:00")
  retained_backups               = coalesce(var.backup_configuration.retained_backups, local.defaults.retained_backups)
  transaction_log_retention_days = coalesce(var.backup_configuration.transaction_log_retention_days, local.defaults.transaction_log_retention_days)

  maintenance_day          = coalesce(var.maintenance_window.day, 7)
  maintenance_hour         = coalesce(var.maintenance_window.hour, 3)
  maintenance_update_track = coalesce(var.maintenance_window.update_track, local.defaults.update_track)

  ssl_mode              = var.require_client_certificate ? "TRUSTED_CLIENT_CERTIFICATE_REQUIRED" : "ENCRYPTED_ONLY"
  connector_enforcement = var.enforce_cloud_sql_connector ? "REQUIRED" : "NOT_REQUIRED"

  # Operational defaults that DBAs can override per workload
  default_database_flags = {
    "log_min_duration_statement" = "1000"
    "log_temp_files"             = "0"
    "pgaudit.log"                = "ddl,role"
    "password_encryption"        = "scram-sha-256"
  }

  # Platform-enforced security, IAM, and audit flags
  mandatory_database_flags = {
    "cloudsql.iam_authentication" = "on"
    "cloudsql.enable_pgaudit"     = "on"
    "log_connections"             = "on"
    "log_disconnections"          = "on"
    "log_checkpoints"             = "on"
    "log_lock_waits"              = "on"
  }

  effective_database_flags = merge(
    local.default_database_flags,
    var.database_flags,
    local.mandatory_database_flags,
  )

  labels = merge(var.labels, {
    managed_by  = "opentofu"
    environment = var.environment
    service     = var.name
    engine      = "postgresql"
  })

  all_instance_names = concat(
    [local.instance_name],
    [for k, _ in var.read_replicas : "${local.instance_name}-ro-${k}"]
  )

  iam_instance_resource_names = [
    for inst in local.all_instance_names :
    "projects/${data.google_project.current.project_id}/instances/${inst}"
  ]

  iam_condition_expression = join(" && ", [
    "resource.type == \"sqladmin.googleapis.com/Instance\"",
    format("(%s)", join(" || ", [
      for res_name in local.iam_instance_resource_names :
      "resource.name == \"${res_name}\""
    ]))
  ])

  iam_principals = merge(
    {
      for u in var.iam_users : "user:${u}" => {
        sql_name = u
        sql_type = "CLOUD_IAM_USER"
        member   = "user:${u}"
      }
    },
    {
      for sa in var.iam_service_accounts : "sa:${sa}" => {
        sql_name = trimsuffix(sa, ".gserviceaccount.com")
        sql_type = "CLOUD_IAM_SERVICE_ACCOUNT"
        member   = "serviceAccount:${sa}"
      }
    },
    {
      for g in var.iam_groups : "group:${g}" => {
        sql_name = g
        sql_type = "CLOUD_IAM_GROUP"
        member   = "group:${g}"
      }
    }
  )
}
