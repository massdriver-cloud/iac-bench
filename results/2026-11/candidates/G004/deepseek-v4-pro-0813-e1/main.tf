provider "aws" {
  alias  = "primary"
  region = var.primary_region
}

provider "aws" {
  alias  = "secondary"
  region = var.secondary_region
}

locals {
  common_tags = merge(var.tags, {
    Environment = var.environment
    Service     = var.name
    ManagedBy   = "opentofu"
  })

  engine_family = "aurora-postgresql${split(".", var.engine_version)[0]}"

  primary_cluster_identifier     = "${var.name}-${var.environment}-primary"
  secondary_cluster_identifier   = "${var.name}-${var.environment}-secondary"
  global_cluster_identifier      = "${var.name}-${var.environment}"
  primary_parameter_group_name   = "${var.name}-${var.environment}-primary"
  secondary_parameter_group_name = "${var.name}-${var.environment}-secondary"
  primary_kms_alias              = "${var.name}-${var.environment}-primary"
  secondary_kms_alias            = "${var.name}-${var.environment}-secondary"
}

# -----------------------------------------------------------------------------
# Customer-managed KMS keys, one in each region, for cluster storage encryption.
# -----------------------------------------------------------------------------
resource "aws_kms_key" "primary" {
  provider = aws.primary

  description             = "Aurora PostgreSQL storage encryption key for ${var.name} (${var.environment}, primary)"
  deletion_window_in_days = var.kms_deletion_window_days
  enable_key_rotation     = true
  tags                    = local.common_tags
}

resource "aws_kms_alias" "primary" {
  provider = aws.primary

  name          = "alias/${local.primary_kms_alias}"
  target_key_id = aws_kms_key.primary.key_id
}

resource "aws_kms_key" "secondary" {
  provider = aws.secondary

  description             = "Aurora PostgreSQL storage encryption key for ${var.name} (${var.environment}, secondary)"
  deletion_window_in_days = var.kms_deletion_window_days
  enable_key_rotation     = true
  tags                    = local.common_tags
}

resource "aws_kms_alias" "secondary" {
  provider = aws.secondary

  name          = "alias/${local.secondary_kms_alias}"
  target_key_id = aws_kms_key.secondary.key_id
}

# -----------------------------------------------------------------------------
# Network plumbing: security groups and DB subnet groups for each region.
# -----------------------------------------------------------------------------
resource "aws_security_group" "primary" {
  provider = aws.primary

  name        = "${local.primary_cluster_identifier}-sg"
  description = "Aurora PostgreSQL access for ${var.name} primary (${var.environment})"
  vpc_id      = var.primary_vpc_id

  ingress {
    description = "PostgreSQL from the ${var.environment} primary VPC (EKS)"
    from_port   = var.port
    to_port     = var.port
    protocol    = "tcp"
    cidr_blocks = [var.primary_vpc_cidr]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.primary_cluster_identifier}-sg"
  })
}

resource "aws_security_group" "secondary" {
  provider = aws.secondary

  name        = "${local.secondary_cluster_identifier}-sg"
  description = "Aurora PostgreSQL access for ${var.name} secondary (${var.environment})"
  vpc_id      = var.secondary_vpc_id

  ingress {
    description = "PostgreSQL from the ${var.environment} secondary VPC (EKS)"
    from_port   = var.port
    to_port     = var.port
    protocol    = "tcp"
    cidr_blocks = [var.secondary_vpc_cidr]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.secondary_cluster_identifier}-sg"
  })
}

resource "aws_db_subnet_group" "primary" {
  provider = aws.primary

  name        = local.primary_cluster_identifier
  subnet_ids  = var.primary_subnet_ids
  description = "Private database subnets for ${var.name} primary (${var.environment})"

  tags = local.common_tags
}

resource "aws_db_subnet_group" "secondary" {
  provider = aws.secondary

  name        = local.secondary_cluster_identifier
  subnet_ids  = var.secondary_subnet_ids
  description = "Private database subnets for ${var.name} secondary (${var.environment})"

  tags = local.common_tags
}

# -----------------------------------------------------------------------------
# Cluster parameter groups. rds.force_ssl = 1 enforces TLS in transit and is
# kept identical in both regions so a global failover does not surprise clients.
# -----------------------------------------------------------------------------
resource "aws_rds_cluster_parameter_group" "primary" {
  provider = aws.primary

  name        = local.primary_parameter_group_name
  family      = local.engine_family
  description = "Aurora PostgreSQL cluster parameters for ${var.name} primary (${var.environment})"

  parameter {
    name         = "rds.force_ssl"
    value        = "1"
    apply_method = "pending-reboot"
  }

  tags = local.common_tags
}

resource "aws_rds_cluster_parameter_group" "secondary" {
  provider = aws.secondary

  name        = local.secondary_parameter_group_name
  family      = local.engine_family
  description = "Aurora PostgreSQL cluster parameters for ${var.name} secondary (${var.environment})"

  parameter {
    name         = "rds.force_ssl"
    value        = "1"
    apply_method = "pending-reboot"
  }

  tags = local.common_tags
}

# -----------------------------------------------------------------------------
# Primary regional Aurora cluster. The master user password is generated and
# stored in AWS Secrets Manager by RDS; applications use IAM authentication.
# -----------------------------------------------------------------------------
resource "aws_rds_cluster" "primary" {
  provider = aws.primary

  cluster_identifier          = local.primary_cluster_identifier
  engine                      = "aurora-postgresql"
  engine_version              = var.engine_version
  database_name               = var.database_name
  master_username             = var.master_username
  manage_master_user_password = true

  db_subnet_group_name            = aws_db_subnet_group.primary.name
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.primary.name
  vpc_security_group_ids          = [aws_security_group.primary.id]

  port                                = var.port
  storage_encrypted                   = true
  kms_key_id                          = aws_kms_key.primary.arn
  iam_database_authentication_enabled = true

  backup_retention_period         = var.backup_retention_period
  preferred_backup_window         = var.preferred_backup_window
  preferred_maintenance_window    = var.preferred_maintenance_window
  enabled_cloudwatch_logs_exports = var.enabled_cloudwatch_logs_exports

  deletion_protection       = var.deletion_protection
  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : "${local.primary_cluster_identifier}-final"

  apply_immediately     = var.apply_immediately
  copy_tags_to_snapshot = true

  tags = local.common_tags
}

# -----------------------------------------------------------------------------
# Aurora Global Database. Cross-region storage replication provides a warm
# secondary cluster and a typical Aurora PostgreSQL global database RPO of
# about one second, so a regional failover meets the "few seconds of writes"
# business requirement.
# -----------------------------------------------------------------------------
resource "aws_rds_global_cluster" "this" {
  provider = aws.primary

  global_cluster_identifier    = local.global_cluster_identifier
  source_db_cluster_identifier = aws_rds_cluster.primary.arn
  force_destroy                = false
}

# -----------------------------------------------------------------------------
# Secondary regional Aurora cluster, attached to the global database.
# -----------------------------------------------------------------------------
resource "aws_rds_cluster" "secondary" {
  provider = aws.secondary

  cluster_identifier        = local.secondary_cluster_identifier
  global_cluster_identifier = aws_rds_global_cluster.this.id

  engine         = "aurora-postgresql"
  engine_version = var.engine_version

  db_subnet_group_name            = aws_db_subnet_group.secondary.name
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.secondary.name
  vpc_security_group_ids          = [aws_security_group.secondary.id]

  port                                = var.port
  storage_encrypted                   = true
  kms_key_id                          = aws_kms_key.secondary.arn
  iam_database_authentication_enabled = true
  enabled_cloudwatch_logs_exports     = var.enabled_cloudwatch_logs_exports

  deletion_protection       = var.deletion_protection
  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : "${local.secondary_cluster_identifier}-final"

  apply_immediately     = var.apply_immediately
  copy_tags_to_snapshot = true

  tags = local.common_tags
}

# -----------------------------------------------------------------------------
# Cluster instances. Primary has a preferred writer plus warm readers; secondary
# instances are all global readers that become usable after a global failover.
# -----------------------------------------------------------------------------
resource "aws_rds_cluster_instance" "primary" {
  provider = aws.primary
  count    = var.primary_instance_count

  identifier         = "${local.primary_cluster_identifier}-${count.index}"
  cluster_identifier = aws_rds_cluster.primary.id
  instance_class     = var.instance_class
  engine             = aws_rds_cluster.primary.engine

  publicly_accessible          = false
  promotion_tier               = count.index == 0 ? 0 : min(count.index, 15)
  auto_minor_version_upgrade   = var.auto_minor_version_upgrade
  performance_insights_enabled = var.performance_insights_enabled
  apply_immediately            = var.apply_immediately

  tags = local.common_tags
}

resource "aws_rds_cluster_instance" "secondary" {
  provider = aws.secondary
  count    = var.secondary_instance_count

  identifier         = "${local.secondary_cluster_identifier}-${count.index}"
  cluster_identifier = aws_rds_cluster.secondary.id
  instance_class     = var.instance_class
  engine             = aws_rds_cluster.secondary.engine

  publicly_accessible          = false
  promotion_tier               = count.index == 0 ? 0 : min(count.index, 15)
  auto_minor_version_upgrade   = var.auto_minor_version_upgrade
  performance_insights_enabled = var.performance_insights_enabled
  apply_immediately            = var.apply_immediately

  tags = local.common_tags
}