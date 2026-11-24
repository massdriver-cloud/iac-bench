data "aws_region" "current" {}

data "aws_partition" "current" {}

locals {
  is_primary   = var.role == "primary"
  engine_major = split(".", var.engine_version)[0]
  # Cluster identifiers are unique per region, so the role suffices.
  cluster_id = "${var.name_prefix}-${var.role}"
  tags = merge(var.tags, {
    Region = data.aws_region.current.name
    Role   = var.role
  })
}

# ---------------------------------------------------------------------------
# Network: the network team owns the VPC and the database subnets.
# ---------------------------------------------------------------------------

data "aws_vpc" "this" {
  filter {
    name   = "tag:Name"
    values = [var.vpc_name]
  }
}

data "aws_subnets" "database" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.this.id]
  }

  filter {
    name   = "tag:tier"
    values = ["database"]
  }
}

data "aws_subnet" "database" {
  for_each = toset(data.aws_subnets.database.ids)
  id       = each.value
}

resource "aws_db_subnet_group" "this" {
  name       = local.cluster_id
  subnet_ids = data.aws_subnets.database.ids
  tags       = local.tags

  lifecycle {
    precondition {
      condition     = length(distinct([for s in data.aws_subnet.database : s.availability_zone])) >= 2
      error_message = "The database-tier subnets in VPC ${var.vpc_name} must span at least 2 availability zones."
    }

    precondition {
      condition     = alltrue([for s in data.aws_subnet.database : !s.map_public_ip_on_launch])
      error_message = "All subnets tagged tier=database must be private (map_public_ip_on_launch = false)."
    }
  }
}

# ---------------------------------------------------------------------------
# Encryption: one customer-managed key per region. Aurora global secondaries
# need a key in their own region, so keys are never shared across regions.
# ---------------------------------------------------------------------------

resource "aws_kms_key" "this" {
  description             = "${var.name_prefix} Aurora ${var.role} cluster (${data.aws_region.current.name})"
  enable_key_rotation     = true
  deletion_window_in_days = var.kms_deletion_window_days
  tags                    = local.tags
}

resource "aws_kms_alias" "this" {
  name          = "alias/${local.cluster_id}-aurora"
  target_key_id = aws_kms_key.this.key_id
}

# ---------------------------------------------------------------------------
# Network access: PostgreSQL 5432 only, from the VPC and explicit extras.
# ---------------------------------------------------------------------------

resource "aws_security_group" "this" {
  name        = "${local.cluster_id}-aurora"
  description = "PostgreSQL access to ${local.cluster_id}"
  vpc_id      = data.aws_vpc.this.id
  tags        = local.tags
}

resource "aws_vpc_security_group_ingress_rule" "cidr" {
  for_each = toset(concat([data.aws_vpc.this.cidr_block], var.allowed_cidr_blocks))

  security_group_id = aws_security_group.this.id
  description       = "PostgreSQL from ${each.value}"
  cidr_ipv4         = each.value
  from_port         = 5432
  to_port           = 5432
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "security_group" {
  for_each = toset(var.allowed_security_group_ids)

  security_group_id            = aws_security_group.this.id
  description                  = "PostgreSQL from security group ${each.value}"
  referenced_security_group_id = each.value
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
}

# ---------------------------------------------------------------------------
# Parameters: TLS enforced, slow-query and connection logging on.
# ---------------------------------------------------------------------------

resource "aws_rds_cluster_parameter_group" "this" {
  name        = local.cluster_id
  family      = "aurora-postgresql${local.engine_major}"
  description = "Cluster parameters for ${local.cluster_id}"
  tags        = local.tags

  parameter {
    name         = "rds.force_ssl"
    value        = "1"
    apply_method = "pending-reboot"
  }

  parameter {
    name         = "log_min_duration_statement"
    value        = "1000"
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

  parameter {
    name         = "idle_in_transaction_session_timeout"
    value        = "60000"
    apply_method = "immediate"
  }
}

# ---------------------------------------------------------------------------
# Enhanced monitoring role (IAM is global, so the name carries the role).
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "monitoring_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["monitoring.rds.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "monitoring" {
  name               = "${local.cluster_id}-rds-monitoring"
  assume_role_policy = data.aws_iam_policy_document.monitoring_assume.json
  tags               = local.tags
}

resource "aws_iam_role_policy_attachment" "monitoring" {
  role       = aws_iam_role.monitoring.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# ---------------------------------------------------------------------------
# The regional Aurora cluster. Primary and secondary differ only in the
# arguments that Aurora Global Database requires to differ.
# ---------------------------------------------------------------------------

resource "aws_rds_cluster" "this" {
  cluster_identifier        = local.cluster_id
  engine                    = "aurora-postgresql"
  engine_version            = var.engine_version
  engine_mode               = "provisioned"
  global_cluster_identifier = var.global_cluster_identifier

  # Primary only: the initial database and the Secrets Manager-managed master.
  database_name               = local.is_primary ? var.database_name : null
  master_username             = local.is_primary ? var.master_username : null
  manage_master_user_password = local.is_primary ? true : null
  master_user_secret_kms_key_id = local.is_primary ? aws_kms_key.this.arn : null

  # Secondary only: the region the replication source lives in.
  source_region = local.is_primary ? null : var.primary_region

  db_subnet_group_name            = aws_db_subnet_group.this.name
  vpc_security_group_ids          = [aws_security_group.this.id]
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.this.name
  port                            = 5432

  storage_encrypted                   = true
  kms_key_id                          = aws_kms_key.this.arn
  iam_database_authentication_enabled = true

  backup_retention_period      = var.backup_retention_days
  preferred_backup_window      = var.preferred_backup_window
  preferred_maintenance_window = var.preferred_maintenance_window
  copy_tags_to_snapshot        = true
  deletion_protection          = var.deletion_protection

  enabled_cloudwatch_logs_exports = ["postgresql"]

  skip_final_snapshot       = false
  final_snapshot_identifier = "${local.cluster_id}-final"

  tags = local.tags
}

resource "aws_rds_cluster_instance" "this" {
  count = var.instance_count

  identifier         = "${local.cluster_id}-${count.index + 1}"
  cluster_identifier = aws_rds_cluster.this.id
  instance_class     = var.instance_class
  engine             = aws_rds_cluster.this.engine
  engine_version     = aws_rds_cluster.this.engine_version

  # Lower tiers are preferred failover targets within the region.
  promotion_tier = count.index

  publicly_accessible          = false
  auto_minor_version_upgrade   = true
  ca_cert_identifier           = "rds-ca-rsa2048-g1"
  performance_insights_enabled = true
  performance_insights_kms_key_id = aws_kms_key.this.arn
  performance_insights_retention_period = var.performance_insights_retention_days

  monitoring_interval = 60
  monitoring_role_arn = aws_iam_role.monitoring.arn

  tags = local.tags
}

# ---------------------------------------------------------------------------
# RPO monitor. AuroraGlobalDBReplicationLag is published in the secondary
# region for the secondary cluster; if it climbs, a regional failover would
# lose more than the agreed few seconds of writes.
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "replication_lag" {
  count = local.is_primary ? 0 : 1

  alarm_name          = "${local.cluster_id}-global-replication-lag"
  alarm_description   = "Aurora Global Database replication lag exceeds the RPO budget for ${local.cluster_id}."
  namespace           = "AWS/RDS"
  metric_name         = "AuroraGlobalDBReplicationLag"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 3
  threshold           = var.replication_lag_alarm_threshold_ms
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "breaching"

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.this.id
  }

  alarm_actions = var.alarm_sns_topic_arn == null ? [] : [var.alarm_sns_topic_arn]
  ok_actions    = var.alarm_sns_topic_arn == null ? [] : [var.alarm_sns_topic_arn]

  tags = local.tags
}
