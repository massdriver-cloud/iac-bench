locals {
  name          = "${var.service_name}-${var.environment}"
  database_name = coalesce(var.database_name, replace(var.service_name, "-", "_"))
  vpc_name      = "apps-${var.environment}"

  engine         = "aurora-postgresql"
  engine_major   = split(".", var.engine_version)[0]
  pg_family      = "aurora-postgresql${local.engine_major}"
  port           = 5432
  log_exports    = ["postgresql"]
  log_group_name = "/aws/rds/cluster/${local.name}/postgresql"

  # Maintenance happens Sunday early-morning US time; backups run just before it.
  backup_window      = "06:00-07:00" # UTC
  maintenance_window = "sun:07:30-sun:08:30"

  common_tags = merge(
    {
      Service     = var.service_name
      Environment = var.environment
      ManagedBy   = "opentofu"
      Module      = "aurora-postgresql-global"
      DataClass   = "customer-payment"
    },
    var.tags,
  )

  # Cluster-level PostgreSQL parameters applied identically in both regions.
  # apply_method = "pending-reboot" is required for static parameters.
  cluster_parameters = [
    { name = "rds.force_ssl", value = "1", apply_method = "immediate" },
    { name = "ssl_min_protocol_version", value = "TLSv1.2", apply_method = "pending-reboot" },
    { name = "password_encryption", value = "scram-sha-256", apply_method = "immediate" },
    { name = "shared_preload_libraries", value = "pg_stat_statements,pgaudit", apply_method = "pending-reboot" },
    { name = "pgaudit.log", value = "ddl,role,misc_set", apply_method = "immediate" },
    { name = "pgaudit.role", value = "rds_pgaudit", apply_method = "immediate" },
    { name = "pgaudit.log_catalog", value = "0", apply_method = "immediate" },
    { name = "log_connections", value = "1", apply_method = "immediate" },
    { name = "log_disconnections", value = "1", apply_method = "immediate" },
    { name = "log_min_duration_statement", value = "1000", apply_method = "immediate" },
    { name = "log_statement", value = "ddl", apply_method = "immediate" },
    { name = "rds.log_retention_period", value = "10080", apply_method = "immediate" },
    { name = "idle_in_transaction_session_timeout", value = "300000", apply_method = "immediate" },
  ]

  primary_cidr_fallback   = length(var.primary_allowed_security_group_ids) == 0 && length(var.allowed_cidr_blocks) == 0
  secondary_cidr_fallback = length(var.secondary_allowed_security_group_ids) == 0 && length(var.allowed_cidr_blocks) == 0

  primary_ingress_cidrs   = local.primary_cidr_fallback ? [data.aws_vpc.primary.cidr_block] : var.allowed_cidr_blocks
  secondary_ingress_cidrs = local.secondary_cidr_fallback ? [data.aws_vpc.secondary.cidr_block] : var.allowed_cidr_blocks
}
