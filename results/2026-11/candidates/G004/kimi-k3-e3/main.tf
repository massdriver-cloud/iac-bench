# =============================================================================
# Standard Aurora PostgreSQL for production services
#
# Every instantiation is an Aurora *global* database spanning the platform's
# two US regions:
#
#   * primary region   - read/write cluster (1 writer + readers across AZs)
#   * secondary region - read-only cluster, continuously replicated
#
# Aurora's storage-level cross-region replication lag is typically well under
# a second, and a managed switchover/failover promotes the secondary within
# minutes. That pairing is what satisfies the business requirement: service
# restored from another region within minutes, with only seconds of writes
# lost.
# =============================================================================

locals {
  # Every identifier derives from service name + environment so multiple
  # instances of this module coexist cleanly in the same account.
  name_prefix = "${var.name}-${var.environment}"

  # The network team names VPCs apps-<environment>; vpc_name is an escape hatch.
  vpc_name = var.vpc_name != null ? var.vpc_name : "apps-${var.environment}"

  engine_major_version   = split(".", var.engine_version)[0]
  parameter_group_family = "aurora-postgresql${local.engine_major_version}"

  # Module-managed KMS keys unless the platform team supplies its own.
  primary_kms_key_arn   = var.primary_kms_key_arn != null ? var.primary_kms_key_arn : one(aws_kms_key.primary[*].arn)
  secondary_kms_key_arn = var.secondary_kms_key_arn != null ? var.secondary_kms_key_arn : one(aws_kms_key.secondary[*].arn)

  default_tags = merge(
    {
      "platform:managed-by"  = "opentofu"
      "platform:module"      = "aurora-postgresql-global"
      "platform:service"     = var.name
      "platform:environment" = var.environment
    },
    var.tags
  )
}

check "regions_differ" {
  assert {
    condition     = var.primary_region != var.secondary_region
    error_message = "primary_region and secondary_region must be different AWS regions - surviving a regional failure is the point of this module."
  }
}

data "aws_caller_identity" "current" {}

# -----------------------------------------------------------------------------
# Network (owned by the network team; discovered by tag, never created here)
# -----------------------------------------------------------------------------

data "aws_vpc" "primary" {
  filter {
    name   = "tag:Name"
    values = [local.vpc_name]
  }
}

data "aws_subnets" "primary" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.primary.id]
  }

  filter {
    name   = "tag:tier"
    values = ["database"]
  }
}

resource "aws_db_subnet_group" "primary" {
  name        = "${local.name_prefix}-primary"
  description = "Private database subnets for ${local.name_prefix} (primary region)"
  subnet_ids  = data.aws_subnets.primary.ids

  tags = { Name = "${local.name_prefix}-primary" }
}

data "aws_vpc" "secondary" {
  provider = aws.secondary

  filter {
    name   = "tag:Name"
    values = [local.vpc_name]
  }
}

data "aws_subnets" "secondary" {
  provider = aws.secondary

  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.secondary.id]
  }

  filter {
    name   = "tag:tier"
    values = ["database"]
  }
}

resource "aws_db_subnet_group" "secondary" {
  provider = aws.secondary

  name        = "${local.name_prefix}-secondary"
  description = "Private database subnets for ${local.name_prefix} (secondary region)"
  subnet_ids  = data.aws_subnets.secondary.ids

  tags = { Name = "${local.name_prefix}-secondary" }
}

# -----------------------------------------------------------------------------
# Access: one security group per cluster. Ingress only from what the caller
# explicitly allows (EKS security groups and/or CIDRs), PostgreSQL port only,
# no egress. Instances are never publicly reachable.
# -----------------------------------------------------------------------------

resource "aws_security_group" "primary" {
  name        = "${local.name_prefix}-db-primary"
  description = "Aurora PostgreSQL ${local.name_prefix} (primary region)"
  vpc_id      = data.aws_vpc.primary.id

  tags = { Name = "${local.name_prefix}-db-primary" }
}

resource "aws_security_group_rule" "primary_security_groups" {
  for_each = toset(var.allowed_security_group_ids.primary)

  type                     = "ingress"
  description              = "PostgreSQL from ${each.value}"
  security_group_id        = aws_security_group.primary.id
  source_security_group_id = each.value
  from_port                = var.port
  to_port                  = var.port
  protocol                 = "tcp"
}

resource "aws_security_group_rule" "primary_cidr_blocks" {
  for_each = toset(var.allowed_cidr_blocks.primary)

  type              = "ingress"
  description       = "PostgreSQL from ${each.value}"
  security_group_id = aws_security_group.primary.id
  cidr_blocks       = [each.value]
  from_port         = var.port
  to_port           = var.port
  protocol          = "tcp"
}

resource "aws_security_group" "secondary" {
  provider = aws.secondary

  name        = "${local.name_prefix}-db-secondary"
  description = "Aurora PostgreSQL ${local.name_prefix} (secondary region)"
  vpc_id      = data.aws_vpc.secondary.id

  tags = { Name = "${local.name_prefix}-db-secondary" }
}

resource "aws_security_group_rule" "secondary_security_groups" {
  provider = aws.secondary

  for_each = toset(var.allowed_security_group_ids.secondary)

  type                     = "ingress"
  description              = "PostgreSQL from ${each.value}"
  security_group_id        = aws_security_group.secondary.id
  source_security_group_id = each.value
  from_port                = var.port
  to_port                  = var.port
  protocol                 = "tcp"
}

resource "aws_security_group_rule" "secondary_cidr_blocks" {
  provider = aws.secondary

  for_each = toset(var.allowed_cidr_blocks.secondary)

  type              = "ingress"
  description       = "PostgreSQL from ${each.value}"
  security_group_id = aws_security_group.secondary.id
  cidr_blocks       = [each.value]
  from_port         = var.port
  to_port           = var.port
  protocol          = "tcp"
}

# -----------------------------------------------------------------------------
# Encryption at rest: one dedicated KMS key per region (KMS keys are regional).
# No explicit key policy: the default policy grants the account root full
# access and delegates control to IAM, which is the AWS-recommended baseline;
# RDS, Secrets Manager and Performance Insights access flows through IAM.
# -----------------------------------------------------------------------------

resource "aws_kms_key" "primary" {
  count = var.primary_kms_key_arn == null ? 1 : 0

  description             = "Aurora PostgreSQL ${local.name_prefix} (primary region)"
  enable_key_rotation     = true
  deletion_window_in_days = 30

  tags = { Name = "${local.name_prefix}-db-primary" }
}

resource "aws_kms_alias" "primary" {
  count = var.primary_kms_key_arn == null ? 1 : 0

  name          = "alias/${local.name_prefix}-db-primary"
  target_key_id = aws_kms_key.primary[0].key_id
}

resource "aws_kms_key" "secondary" {
  provider = aws.secondary

  count = var.secondary_kms_key_arn == null ? 1 : 0

  description             = "Aurora PostgreSQL ${local.name_prefix} (secondary region)"
  enable_key_rotation     = true
  deletion_window_in_days = 30

  tags = { Name = "${local.name_prefix}-db-secondary" }
}

resource "aws_kms_alias" "secondary" {
  provider = aws.secondary

  count = var.secondary_kms_key_arn == null ? 1 : 0

  name          = "alias/${local.name_prefix}-db-secondary"
  target_key_id = aws_kms_key.secondary[0].key_id
}

# -----------------------------------------------------------------------------
# Cluster parameter groups (regional resources, so one per region).
# Payment/customer data: SSL is mandatory and connections are audited.
# -----------------------------------------------------------------------------

resource "aws_rds_cluster_parameter_group" "primary" {
  name        = "${local.name_prefix}-primary"
  family      = local.parameter_group_family
  description = "Aurora PostgreSQL ${local.name_prefix} cluster parameters"

  parameter {
    name         = "rds.force_ssl"
    value        = "1"
    apply_method = "pending-reboot"
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

  tags = { Name = "${local.name_prefix}-primary" }
}

resource "aws_rds_cluster_parameter_group" "secondary" {
  provider = aws.secondary

  name        = "${local.name_prefix}-secondary"
  family      = local.parameter_group_family
  description = "Aurora PostgreSQL ${local.name_prefix} cluster parameters"

  parameter {
    name         = "rds.force_ssl"
    value        = "1"
    apply_method = "pending-reboot"
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

  tags = { Name = "${local.name_prefix}-secondary" }
}

# -----------------------------------------------------------------------------
# Enhanced monitoring role (IAM is global; one role serves both regions)
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "enhanced_monitoring_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["monitoring.rds.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "enhanced_monitoring" {
  name               = "${local.name_prefix}-rds-enhanced-monitoring"
  description        = "RDS enhanced monitoring for Aurora PostgreSQL ${local.name_prefix}"
  assume_role_policy = data.aws_iam_policy_document.enhanced_monitoring_assume.json
}

resource "aws_iam_role_policy_attachment" "enhanced_monitoring" {
  role       = aws_iam_role.enhanced_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# -----------------------------------------------------------------------------
# The global database
# -----------------------------------------------------------------------------

resource "aws_rds_global_cluster" "this" {
  global_cluster_identifier = local.name_prefix
  engine                    = "aurora-postgresql"
  engine_version            = var.engine_version
  database_name             = var.database_name
  storage_encrypted         = true
}

# -----------------------------------------------------------------------------
# Primary region: read/write cluster
# -----------------------------------------------------------------------------

resource "aws_rds_cluster" "primary" {
  cluster_identifier = "${local.name_prefix}-primary"
  engine             = aws_rds_global_cluster.this.engine
  engine_version     = aws_rds_global_cluster.this.engine_version

  global_cluster_identifier = aws_rds_global_cluster.this.id

  # Master credentials live on the initial primary only; the password is
  # generated by RDS and kept in Secrets Manager (never in Terraform state).
  master_username               = var.master_username
  manage_master_user_password   = true
  master_user_secret_kms_key_id = local.primary_kms_key_arn

  db_subnet_group_name            = aws_db_subnet_group.primary.name
  vpc_security_group_ids          = [aws_security_group.primary.id]
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.primary.name
  port                            = var.port
  storage_type                    = var.storage_type

  # storage_encrypted is inherited from the global cluster; the KMS key is
  # chosen per region.
  kms_key_id = local.primary_kms_key_arn

  # Services run on EKS and reach AWS through IAM roles: IAM database
  # authentication is on so applications connect without stored passwords.
  iam_database_authentication_enabled = true

  backup_retention_period      = var.backup_retention_period
  preferred_backup_window      = var.backup_window
  preferred_maintenance_window = var.maintenance_window
  copy_tags_to_snapshot        = true
  skip_final_snapshot          = var.skip_final_snapshot
  final_snapshot_identifier    = var.skip_final_snapshot ? null : "${local.name_prefix}-primary-final"

  enabled_cloudwatch_logs_exports = var.cloudwatch_log_exports

  deletion_protection = var.deletion_protection
  apply_immediately   = var.apply_immediately

  tags = { Name = "${local.name_prefix}-primary" }
}

resource "aws_rds_cluster_instance" "primary" {
  count = var.primary_instance_count

  identifier         = "${local.name_prefix}-primary-${count.index + 1}"
  cluster_identifier = aws_rds_cluster.primary.id
  engine             = aws_rds_cluster.primary.engine
  engine_version     = aws_rds_cluster.primary.engine_version
  instance_class     = var.instance_class

  publicly_accessible = false
  promotion_tier      = count.index

  performance_insights_enabled          = true
  performance_insights_kms_key_id       = local.primary_kms_key_arn
  performance_insights_retention_period = var.performance_insights_retention_period

  monitoring_interval = var.monitoring_interval
  monitoring_role_arn = var.monitoring_interval > 0 ? aws_iam_role.enhanced_monitoring.arn : null

  auto_minor_version_upgrade = var.auto_minor_version_upgrade
  apply_immediately          = var.apply_immediately
  copy_tags_to_snapshot      = true

  tags = { Name = "${local.name_prefix}-primary-${count.index + 1}" }
}

# -----------------------------------------------------------------------------
# Secondary region: read-only standby cluster (the DR target)
# -----------------------------------------------------------------------------

resource "aws_rds_cluster" "secondary" {
  provider = aws.secondary

  cluster_identifier = "${local.name_prefix}-secondary"
  engine             = aws_rds_global_cluster.this.engine
  engine_version     = aws_rds_global_cluster.this.engine_version

  global_cluster_identifier = aws_rds_global_cluster.this.id

  db_subnet_group_name            = aws_db_subnet_group.secondary.name
  vpc_security_group_ids          = [aws_security_group.secondary.id]
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.secondary.name
  port                            = var.port
  storage_type                    = var.storage_type

  kms_key_id = local.secondary_kms_key_arn

  iam_database_authentication_enabled = true

  backup_retention_period      = var.backup_retention_period
  preferred_backup_window      = var.backup_window
  preferred_maintenance_window = var.maintenance_window
  copy_tags_to_snapshot        = true
  skip_final_snapshot          = var.skip_final_snapshot
  final_snapshot_identifier    = var.skip_final_snapshot ? null : "${local.name_prefix}-secondary-final"

  enabled_cloudwatch_logs_exports = var.cloudwatch_log_exports

  deletion_protection = var.deletion_protection
  apply_immediately   = var.apply_immediately

  tags = { Name = "${local.name_prefix}-secondary" }

  # AWS requires the primary cluster to be fully available (including its
  # instances) before a secondary region can join the global cluster.
  depends_on = [aws_rds_cluster_instance.primary]
}

resource "aws_rds_cluster_instance" "secondary" {
  provider = aws.secondary

  count = var.secondary_instance_count

  identifier         = "${local.name_prefix}-secondary-${count.index + 1}"
  cluster_identifier = aws_rds_cluster.secondary.id
  engine             = aws_rds_cluster.secondary.engine
  engine_version     = aws_rds_cluster.secondary.engine_version
  instance_class     = var.instance_class

  publicly_accessible = false
  promotion_tier      = count.index

  performance_insights_enabled          = true
  performance_insights_kms_key_id       = local.secondary_kms_key_arn
  performance_insights_retention_period = var.performance_insights_retention_period

  monitoring_interval = var.monitoring_interval
  monitoring_role_arn = var.monitoring_interval > 0 ? aws_iam_role.enhanced_monitoring.arn : null

  auto_minor_version_upgrade = var.auto_minor_version_upgrade
  apply_immediately          = var.apply_immediately
  copy_tags_to_snapshot      = true

  tags = { Name = "${local.name_prefix}-secondary-${count.index + 1}" }
}
