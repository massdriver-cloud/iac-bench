locals {
  engine        = "aurora-postgresql"
  engine_major  = split(".", var.engine_version)[0]
  engine_family = "aurora-postgresql${local.engine_major}"

  base_name = "${var.name}-${var.environment}"

  global_cluster_id    = "${local.base_name}-global"
  primary_cluster_id   = "${local.base_name}-${var.primary_region}"
  secondary_cluster_id = "${local.base_name}-${var.secondary_region}"

  database_name = coalesce(var.database_name, replace(var.name, "-", "_"))
  vpc_name      = "apps-${var.environment}"

  default_tags = merge(
    {
      ManagedBy   = "opentofu"
      Module      = "aurora-postgresql-global"
      Service     = var.name
      Environment = var.environment
    },
    var.tags,
  )

  # Production defaults applied to every database. Consumers can append to or
  # override individual entries via var.cluster_parameter_group_parameters
  # (later entries with the same name win).
  default_cluster_parameters = [
    # Customer/payment data: TLS is not optional.
    { name = "rds.force_ssl", value = "1", apply_method = "pending-reboot" },
    # Query statistics for dashboards and troubleshooting.
    { name = "shared_preload_libraries", value = "pg_stat_statements", apply_method = "pending-reboot" },
    # Audit trail over who touches the data.
    { name = "log_connections", value = "1", apply_method = "immediate" },
    { name = "log_disconnections", value = "1", apply_method = "immediate" },
    { name = "log_statement", value = "ddl", apply_method = "immediate" },
    { name = "log_lock_waits", value = "1", apply_method = "immediate" },
    # Slow-query log: anything over 1s.
    { name = "log_min_duration_statement", value = "1000", apply_method = "immediate" },
    # Log sort/hash spills above 256 MB.
    { name = "log_temp_files", value = "262144", apply_method = "immediate" },
  ]

  cluster_parameters = {
    for p in concat(local.default_cluster_parameters, var.cluster_parameter_group_parameters) : p.name => p
  }
}
