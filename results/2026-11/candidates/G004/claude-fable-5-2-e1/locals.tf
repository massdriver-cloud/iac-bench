locals {
  name = "${var.service}-${var.environment}"

  # Each regional cluster is named after the region it lives in, not after its
  # role: after a failover the roles swap, the names stay true.
  cluster_ids = {
    primary   = "${local.name}-${var.primary_region}"
    secondary = "${local.name}-${var.secondary_region}"
  }

  database_name      = coalesce(var.database_name, replace(var.service, "-", "_"))
  iam_database_users = coalesce(var.iam_database_users, [replace(var.service, "-", "_")])
  port               = 5432

  engine                 = "aurora-postgresql"
  engine_major_version   = split(".", var.engine_version)[0]
  parameter_group_family = "aurora-postgresql${local.engine_major_version}"

  instance_keys = toset([for i in range(1, var.instances_per_region + 1) : tostring(i)])

  # Settings the module enforces on every cluster. Both regions get the same
  # values because either may be the writer.
  cluster_parameters = concat(
    [
      # Reject any connection that is not TLS-encrypted.
      { name = "rds.force_ssl", value = "1", apply_method = "immediate" },
      # Audit trail for systems holding customer and payment data: who
      # connected, and every schema or permission change.
      { name = "log_connections", value = "1", apply_method = "immediate" },
      { name = "log_disconnections", value = "1", apply_method = "immediate" },
      { name = "shared_preload_libraries", value = "pg_stat_statements,pgaudit", apply_method = "pending-reboot" },
      { name = "pgaudit.log", value = "ddl,role", apply_method = "immediate" },
    ],
    var.enforced_rpo_seconds == null ? [] : [
      { name = "rds.global_db_rpo", value = tostring(var.enforced_rpo_seconds), apply_method = "immediate" },
    ],
  )

  tags = merge(var.tags, {
    service             = var.service
    environment         = var.environment
    managed-by          = "opentofu"
    data-classification = "restricted"
  })
}
