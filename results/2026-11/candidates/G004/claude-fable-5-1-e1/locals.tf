locals {
  name          = "${var.service_name}-${var.environment}"
  vpc_name      = "apps-${var.environment}"
  database_name = coalesce(var.database_name, replace(var.service_name, "-", "_"))

  primary_cluster_id   = "${local.name}-${var.primary_region}"
  secondary_cluster_id = "${local.name}-${var.secondary_region}"

  common_tags = merge(
    {
      Service     = var.service_name
      Environment = var.environment
      ManagedBy   = "opentofu"
      Module      = "aurora-postgresql-global"
      DataClass   = "confidential"
    },
    var.tags,
  )

  # Security-group ingress sources. Empty CIDR list => entire VPC CIDR.
  primary_ingress_cidrs   = length(var.allowed_cidr_blocks.primary) > 0 ? var.allowed_cidr_blocks.primary : [data.aws_vpc.primary.cidr_block]
  secondary_ingress_cidrs = length(var.allowed_cidr_blocks.secondary) > 0 ? var.allowed_cidr_blocks.secondary : [data.aws_vpc.secondary.cidr_block]

  # Cluster-level PostgreSQL parameters: TLS only, modern password hashing, audit-friendly logging.
  cluster_parameters = {
    "rds.force_ssl"              = { value = "1", apply_method = "pending-reboot" }
    "password_encryption"        = { value = "scram-sha-256", apply_method = "immediate" }
    "log_connections"            = { value = "1", apply_method = "immediate" }
    "log_disconnections"         = { value = "1", apply_method = "immediate" }
    "log_statement"              = { value = "ddl", apply_method = "immediate" }
    "log_min_duration_statement" = { value = tostring(var.log_min_duration_statement_ms), apply_method = "immediate" }
    "log_lock_waits"             = { value = "1", apply_method = "immediate" }
    "rds.log_retention_period"   = { value = "10080", apply_method = "immediate" }
    "shared_preload_libraries"   = { value = "pg_stat_statements", apply_method = "pending-reboot" }
    "pg_stat_statements.track"   = { value = "all", apply_method = "immediate" }
  }

  # Instance-level parameters (identical today; kept separate so instance-only tuning has a home).
  instance_parameters = {
    "log_temp_files" = { value = "0", apply_method = "immediate" }
  }

  parameter_group_family = "aurora-postgresql${split(".", var.engine_version)[0]}"
}
