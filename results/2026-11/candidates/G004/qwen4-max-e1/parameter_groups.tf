# ---------------------------------------------------------------------------
# Engine hardening, applied via the primary cluster parameter group. Aurora
# global databases replicate cluster parameters to the secondary region, so
# the DR cluster enforces the same policy after failover.
#
#  * rds.force_ssl        - reject any non-TLS connection (customer/payment data)
#  * pgaudit              - audit DDL and role/permission changes to the
#                           postgresql CloudWatch log export
#  * log_connections / log_disconnections - session audit trail
# ---------------------------------------------------------------------------

resource "aws_rds_cluster_parameter_group" "primary" {
  name_prefix = "${local.name}-"
  family      = local.pg_family
  description = "Hardened parameters for ${local.name}"
  tags        = var.tags

  parameter {
    name         = "rds.force_ssl"
    value        = "1"
    apply_method = "pending-reboot"
  }

  parameter {
    name         = "shared_preload_libraries"
    value        = "pg_stat_statements,pgaudit"
    apply_method = "pending-reboot"
  }

  parameter {
    name         = "pgaudit.log"
    value        = "ddl,role"
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

  lifecycle {
    create_before_destroy = true
  }
}
