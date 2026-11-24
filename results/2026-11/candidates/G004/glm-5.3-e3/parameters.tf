###############################################################################
# Cluster parameter groups — one per region, identical content.
#
# The parameters encode the compliance posture for customer/payment data:
#   - rds.force_ssl       → connections without TLS are refused outright;
#   - shared_preload_libraries/pgaudit.log → pgAudit session auditing,
#     exported to the region's CloudWatch audit log group.
#
# Parameter groups are regional resources, so the DR region needs its own copy
# with the same definition — after promotion the DR cluster keeps enforcing
# the same rules as the primary did.
###############################################################################

resource "aws_rds_cluster_parameter_group" "primary" {
  provider    = aws.primary
  name_prefix = "${local.name}-"
  family      = local.parameter_group_family
  description = "${local.name} Aurora PostgreSQL: TLS enforced, pgAudit enabled (primary)"

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
    value        = local.pgaudit_log
    apply_method = "immediate"
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "${local.primary_cluster_identifier}"
  }
}

resource "aws_rds_cluster_parameter_group" "secondary" {
  provider    = aws.secondary
  name_prefix = "${local.name}-"
  family      = local.parameter_group_family
  description = "${local.name} Aurora PostgreSQL: TLS enforced, pgAudit enabled (DR)"

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
    value        = local.pgaudit_log
    apply_method = "immediate"
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "${local.secondary_cluster_identifier}"
  }
}
