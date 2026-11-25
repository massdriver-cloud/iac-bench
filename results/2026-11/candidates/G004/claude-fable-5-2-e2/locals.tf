locals {
  name          = "${var.service}-${var.environment}"
  vpc_name      = "apps-${var.environment}"
  database_name = coalesce(var.database_name, replace(var.service, "-", "_"))
  port          = 5432

  engine                 = "aurora-postgresql"
  engine_major_version   = split(".", var.engine_version)[0]
  parameter_group_family = "aurora-postgresql${local.engine_major_version}"

  cluster_identifiers = {
    primary   = "${local.name}-${var.primary_region}"
    secondary = "${local.name}-${var.secondary_region}"
  }

  tags = merge(
    {
      Service     = var.service
      Environment = var.environment
      ManagedBy   = "opentofu"
    },
    var.tags,
  )

  # Cluster parameters, identical in both regions so that whichever region is
  # the writer behaves the same.
  cluster_parameters = concat(
    [
      # Encryption in transit: reject non-TLS connections, TLS 1.2 minimum.
      { name = "rds.force_ssl", value = "1", apply_method = "immediate" },
      { name = "ssl_min_protocol_version", value = "TLSv1.2", apply_method = "pending-reboot" },
      # Audit trail for a database holding customer and payment data:
      # who connected, and every schema / privilege change.
      { name = "log_connections", value = "1", apply_method = "immediate" },
      { name = "log_disconnections", value = "1", apply_method = "immediate" },
      { name = "shared_preload_libraries", value = "pg_stat_statements,pgaudit", apply_method = "pending-reboot" },
      { name = "pgaudit.log", value = "ddl,role", apply_method = "immediate" },
    ],
    var.managed_rpo_seconds == null ? [] : [
      # Managed RPO: caps data loss on a cross-region failover.
      { name = "rds.global_db_rpo", value = tostring(var.managed_rpo_seconds), apply_method = "immediate" },
    ],
  )
}

data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}
