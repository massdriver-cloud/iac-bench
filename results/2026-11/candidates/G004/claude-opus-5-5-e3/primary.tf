# ---------------------------------------------------------------------------
# Primary region: writer cluster
# ---------------------------------------------------------------------------

resource "aws_db_subnet_group" "primary" {
  name        = local.primary_cluster_id
  description = "Database subnets for ${local.name}"
  subnet_ids  = data.aws_subnets.primary.ids

  lifecycle {
    precondition {
      condition     = length(data.aws_subnets.primary.ids) >= 2
      error_message = "At least two subnets tagged tier=database are required in the primary VPC."
    }
  }
}

resource "aws_security_group" "primary" {
  name        = "${local.primary_cluster_id}-aurora"
  description = "Aurora PostgreSQL ${local.name}"
  vpc_id      = data.aws_vpc.primary.id

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "primary_sg" {
  for_each = toset(var.primary_allowed_security_group_ids)

  security_group_id            = aws_security_group.primary.id
  description                  = "PostgreSQL from ${each.value}"
  ip_protocol                  = "tcp"
  from_port                    = local.port
  to_port                      = local.port
  referenced_security_group_id = each.value
}

resource "aws_vpc_security_group_ingress_rule" "primary_cidr" {
  for_each = length(var.primary_allowed_security_group_ids) == 0 ? toset([for a in data.aws_vpc.primary.cidr_block_associations : a.cidr_block]) : toset([])

  security_group_id = aws_security_group.primary.id
  description       = "PostgreSQL from ${local.vpc_name} VPC"
  ip_protocol       = "tcp"
  from_port         = local.port
  to_port           = local.port
  cidr_ipv4         = each.value
}

resource "aws_rds_cluster_parameter_group" "primary" {
  name_prefix = "${local.name}-"
  family      = local.family
  description = "Aurora PostgreSQL ${local.name} cluster parameters"

  dynamic "parameter" {
    for_each = local.cluster_parameters
    content {
      name         = parameter.value.name
      value        = parameter.value.value
      apply_method = parameter.value.apply_method
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_cloudwatch_log_group" "primary" {
  name              = "/aws/rds/cluster/${local.primary_cluster_id}/postgresql"
  retention_in_days = var.log_retention_days
  kms_key_id        = aws_kms_key.primary.arn
}

resource "aws_rds_cluster" "primary" {
  cluster_identifier        = local.primary_cluster_id
  global_cluster_identifier = aws_rds_global_cluster.this.id
  engine                    = aws_rds_global_cluster.this.engine
  engine_version            = aws_rds_global_cluster.this.engine_version
  database_name             = local.database_name
  port                      = local.port

  master_username = var.master_username
  master_password = random_password.master.result

  db_subnet_group_name            = aws_db_subnet_group.primary.name
  vpc_security_group_ids          = [aws_security_group.primary.id]
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.primary.name

  storage_encrypted                   = true
  kms_key_id                          = aws_kms_key.primary.arn
  iam_database_authentication_enabled = true

  backup_retention_period      = var.backup_retention_days
  preferred_backup_window      = var.preferred_backup_window
  preferred_maintenance_window = var.preferred_maintenance_window
  copy_tags_to_snapshot        = true
  deletion_protection          = var.deletion_protection
  skip_final_snapshot          = false
  final_snapshot_identifier    = "${local.primary_cluster_id}-final"

  enabled_cloudwatch_logs_exports = ["postgresql"]

  depends_on = [aws_cloudwatch_log_group.primary]

  lifecycle {
    # Minor version upgrades of a global database are performed on the
    # global cluster; after a managed failover/switchover the roles of the
    # regional clusters swap, which must not be "corrected" by tofu.
    ignore_changes = [replication_source_identifier, global_cluster_identifier]
  }
}

resource "aws_rds_cluster_instance" "primary" {
  count = var.primary_instance_count

  identifier         = "${local.primary_cluster_id}-${count.index + 1}"
  cluster_identifier = aws_rds_cluster.primary.id
  engine             = aws_rds_cluster.primary.engine
  engine_version     = aws_rds_cluster.primary.engine_version
  instance_class     = var.instance_class

  db_subnet_group_name       = aws_db_subnet_group.primary.name
  publicly_accessible        = false
  auto_minor_version_upgrade = false
  ca_cert_identifier         = "rds-ca-rsa2048-g1"
  promotion_tier             = count.index == 0 ? 0 : 1

  performance_insights_enabled          = true
  performance_insights_kms_key_id       = aws_kms_key.primary.arn
  performance_insights_retention_period = 7
  monitoring_interval                   = 30
  monitoring_role_arn                   = aws_iam_role.monitoring.arn

  depends_on = [aws_iam_role_policy_attachment.monitoring]
}
