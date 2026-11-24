#
# Cluster parameter groups are regional. Production PostgreSQL databases for
# customer/payment data should require TLS for every client connection.
#

resource "aws_rds_cluster_parameter_group" "primary" {
  provider = aws.primary

  name        = "${local.prefix}-primary-pg"
  family      = local.engine_family
  description = "Aurora PostgreSQL cluster parameters for ${var.service_name} (${var.environment}) primary"

  parameter {
    name         = "rds.force_ssl"
    value        = "1"
    apply_method = "pending-reboot"
  }

  tags = local.default_tags
}

resource "aws_rds_cluster_parameter_group" "secondary" {
  provider = aws.secondary

  name        = "${local.prefix}-secondary-pg"
  family      = local.engine_family
  description = "Aurora PostgreSQL cluster parameters for ${var.service_name} (${var.environment}) secondary"

  parameter {
    name         = "rds.force_ssl"
    value        = "1"
    apply_method = "pending-reboot"
  }

  tags = local.default_tags
}