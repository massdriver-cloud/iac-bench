# The cluster parameter group lives in the primary region and is inherited by
# the secondary: in an Aurora global database, parameter changes made on the
# primary cluster are replicated to the secondary. The hardening below is
# therefore defined exactly once.
#
#  - rds.force_ssl           : TLS is mandatory for every connection
#  - pgaudit                 : SQL-level audit trail for customer/payment data
#  - log_connections/_logs   : connection auditing into CloudWatch Logs

resource "aws_rds_cluster_parameter_group" "primary" {
  provider    = aws.primary
  name        = "${local.name}-${var.primary_region}-params"
  family      = local.parameter_family
  description = "Hardened PostgreSQL defaults for the ${var.name} (${var.environment}) Aurora global database"

  parameter {
    name         = "rds.force_ssl"
    value        = "1"
    apply_method = "immediate"
  }

  parameter {
    name         = "shared_preload_libraries"
    value        = "pgaudit"
    apply_method = "pending-reboot"
  }

  parameter {
    name         = "pgaudit.log"
    value        = local.pgaudit_log_csv
    apply_method = "immediate"
  }

  parameter {
    name         = "log_connections"
    value        = "1"
    apply_method = "immediate"
  }

  parameter {
    name         = "log_disconnections"
    value        = "1"
    apply_method = "immediate"
  }

  tags = {
    Name = "${local.name}-${var.primary_region}-params"
  }
}
