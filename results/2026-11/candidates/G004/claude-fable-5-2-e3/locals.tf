data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  name = "${var.service}-${var.environment}"

  # Clusters are named after the region they live in, not after their role:
  # "primary" and "secondary" swap when the database fails over, regions don't.
  cluster_identifiers = {
    primary   = "${local.name}-${var.primary_region}"
    secondary = "${local.name}-${var.secondary_region}"
  }

  database_name   = coalesce(var.database_name, replace(var.service, "-", "_"))
  master_username = "dbadmin"
  port            = 5432

  engine                 = "aurora-postgresql"
  parameter_group_family = "aurora-postgresql${split(".", var.engine_version)[0]}"

  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition

  tags = merge(var.tags, {
    service     = var.service
    environment = var.environment
    managed-by  = "opentofu"
  })

  # Settings shared by the cluster parameter group in both regions, so the
  # database behaves the same whichever region is currently the writer.
  cluster_parameters = merge(
    {
      # Refuse unencrypted client connections.
      "rds.force_ssl" = "1"
      # Audit trail: who connected, when, and every schema change. Statement
      # and slow-query logging stay off on purpose: they would copy customer
      # and payment values from query text into the logs.
      "log_connections"    = "1"
      "log_disconnections" = "1"
      "log_statement"      = "ddl"
    },
    var.enforced_rpo_seconds == null ? {} : {
      "rds.global_db_rpo" = tostring(var.enforced_rpo_seconds)
    }
  )
}
