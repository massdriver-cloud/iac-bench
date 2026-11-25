data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

locals {
  name         = "${var.service_name}-${var.environment}"
  vpc_name     = "apps-${var.environment}"
  account_id   = data.aws_caller_identity.current.account_id
  partition    = data.aws_partition.current.partition
  major        = regex("^[0-9]+", var.engine_version)
  param_family = "aurora-postgresql${local.major}"
}

# ---------------------------------------------------------------------------
# Network: the network team owns the VPCs and the tier=database subnets.
# ---------------------------------------------------------------------------

data "aws_vpc" "primary" {
  tags = {
    Name = local.vpc_name
  }
}

data "aws_vpc" "secondary" {
  provider = aws.secondary

  tags = {
    Name = local.vpc_name
  }
}

data "aws_subnets" "primary_db" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.primary.id]
  }

  filter {
    name   = "tag:tier"
    values = ["database"]
  }
}

data "aws_subnets" "secondary_db" {
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

resource "aws_db_subnet_group" "primary" {
  name        = "${local.name}-${var.primary_region}"
  subnet_ids  = data.aws_subnets.primary_db.ids
  description = "Database subnets for ${local.name} in ${var.primary_region}"

  lifecycle {
    precondition {
      condition     = length(data.aws_subnets.primary_db.ids) >= 2
      error_message = "The ${local.vpc_name} VPC in ${var.primary_region} needs at least 2 subnets tagged tier=database in different AZs."
    }
  }
}

resource "aws_db_subnet_group" "secondary" {
  provider = aws.secondary

  name        = "${local.name}-${var.secondary_region}"
  subnet_ids  = data.aws_subnets.secondary_db.ids
  description = "Database subnets for ${local.name} in ${var.secondary_region}"

  lifecycle {
    precondition {
      condition     = length(data.aws_subnets.secondary_db.ids) >= 2
      error_message = "The ${local.vpc_name} VPC in ${var.secondary_region} needs at least 2 subnets tagged tier=database in different AZs."
    }
  }
}

resource "aws_security_group" "primary" {
  name_prefix = "${local.name}-db-"
  description = "PostgreSQL access to ${local.name} in ${var.primary_region}"
  vpc_id      = data.aws_vpc.primary.id

  ingress {
    description = "PostgreSQL from the regional VPC and approved extra CIDRs"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = concat([data.aws_vpc.primary.cidr_block], var.additional_ingress_cidrs)
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "secondary" {
  provider = aws.secondary

  name_prefix = "${local.name}-db-"
  description = "PostgreSQL access to ${local.name} in ${var.secondary_region}"
  vpc_id      = data.aws_vpc.secondary.id

  ingress {
    description = "PostgreSQL from the regional VPC and approved extra CIDRs"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = concat([data.aws_vpc.secondary.cidr_block], var.additional_ingress_cidrs)
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ---------------------------------------------------------------------------
# Encryption: KMS keys are regional, so each cluster gets its own key.
# ---------------------------------------------------------------------------

resource "aws_kms_key" "primary" {
  description             = "Aurora storage, performance insights and master secret for ${local.name} (${var.primary_region})"
  enable_key_rotation     = true
  deletion_window_in_days = 30
}

resource "aws_kms_alias" "primary" {
  name          = "alias/${local.name}-aurora-${var.primary_region}"
  target_key_id = aws_kms_key.primary.key_id
}

resource "aws_kms_key" "secondary" {
  provider = aws.secondary

  description             = "Aurora storage and performance insights for ${local.name} (${var.secondary_region})"
  enable_key_rotation     = true
  deletion_window_in_days = 30
}

resource "aws_kms_alias" "secondary" {
  provider = aws.secondary

  name          = "alias/${local.name}-aurora-${var.secondary_region}"
  target_key_id = aws_kms_key.secondary.key_id
}

# ---------------------------------------------------------------------------
# Parameters: enforce TLS and log slow statements in both regions.
# ---------------------------------------------------------------------------

resource "aws_rds_cluster_parameter_group" "primary" {
  name        = "${local.name}-${var.primary_region}"
  family      = local.param_family
  description = "Cluster parameters for ${local.name}"

  parameter {
    name         = "rds.force_ssl"
    value        = "1"
    apply_method = "immediate"
  }

  parameter {
    name         = "log_min_duration_statement"
    value        = "1000"
    apply_method = "immediate"
  }
}

resource "aws_rds_cluster_parameter_group" "secondary" {
  provider = aws.secondary

  name        = "${local.name}-${var.secondary_region}"
  family      = local.param_family
  description = "Cluster parameters for ${local.name}"

  parameter {
    name         = "rds.force_ssl"
    value        = "1"
    apply_method = "immediate"
  }

  parameter {
    name         = "log_min_duration_statement"
    value        = "1000"
    apply_method = "immediate"
  }
}

# ---------------------------------------------------------------------------
# Enhanced monitoring role (IAM is global, so one role serves both regions).
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "monitoring_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["monitoring.rds.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "monitoring" {
  name               = "${local.name}-rds-monitoring"
  assume_role_policy = data.aws_iam_policy_document.monitoring_assume.json
}

resource "aws_iam_role_policy_attachment" "monitoring" {
  role       = aws_iam_role.monitoring.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# ---------------------------------------------------------------------------
# Global database. The primary writer cluster is created below; the secondary
# cluster joins it after the primary has instances.
# ---------------------------------------------------------------------------

resource "aws_rds_global_cluster" "this" {
  global_cluster_identifier = local.name
  engine                    = "aurora-postgresql"
  engine_version            = var.engine_version
  storage_encrypted         = true
  deletion_protection       = var.deletion_protection
  force_destroy             = false

  lifecycle {
    precondition {
      condition     = var.primary_region != var.secondary_region
      error_message = "primary_region and secondary_region must be different regions."
    }
  }
}

# ---------------------------------------------------------------------------
# Primary (writer) cluster in var.primary_region.
# ---------------------------------------------------------------------------

resource "aws_rds_cluster" "primary" {
  cluster_identifier        = "${local.name}-${var.primary_region}"
  global_cluster_identifier = aws_rds_global_cluster.this.id

  engine         = aws_rds_global_cluster.this.engine
  engine_version = var.engine_version

  database_name                 = var.database_name
  master_username               = var.master_username
  manage_master_user_password   = true
  master_user_secret_kms_key_id = aws_kms_key.primary.arn

  storage_encrypted = true
  kms_key_id        = aws_kms_key.primary.arn

  db_subnet_group_name            = aws_db_subnet_group.primary.name
  vpc_security_group_ids          = [aws_security_group.primary.id]
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.primary.name

  iam_database_authentication_enabled = true
  deletion_protection                 = var.deletion_protection

  backup_retention_period      = var.backup_retention_days
  preferred_backup_window      = var.backup_window
  preferred_maintenance_window = var.maintenance_window
  copy_tags_to_snapshot        = true

  enabled_cloudwatch_logs_exports = ["postgresql"]

  skip_final_snapshot       = false
  final_snapshot_identifier = "${local.name}-${var.primary_region}-final-${formatdate("YYYYMMDDhhmmss", timestamp())}"

  lifecycle {
    ignore_changes = [final_snapshot_identifier]
  }
}

resource "aws_rds_cluster_instance" "primary" {
  count = var.instance_count

  identifier         = "${local.name}-${var.primary_region}-${count.index + 1}"
  cluster_identifier = aws_rds_cluster.primary.id

  engine         = aws_rds_cluster.primary.engine
  engine_version = var.engine_version
  instance_class = var.instance_class

  # Lower tier = preferred failover target inside the region.
  promotion_tier             = count.index
  publicly_accessible        = false
  auto_minor_version_upgrade = true

  performance_insights_enabled    = true
  performance_insights_kms_key_id = aws_kms_key.primary.arn

  monitoring_interval = 60
  monitoring_role_arn = aws_iam_role.monitoring.arn
}

# ---------------------------------------------------------------------------
# Secondary (read-only, promotable) cluster in var.secondary_region.
# It has no master credentials of its own; it inherits them on promotion.
# ---------------------------------------------------------------------------

resource "aws_rds_cluster" "secondary" {
  provider = aws.secondary

  cluster_identifier        = "${local.name}-${var.secondary_region}"
  global_cluster_identifier = aws_rds_global_cluster.this.id

  engine         = aws_rds_global_cluster.this.engine
  engine_version = var.engine_version

  storage_encrypted = true
  kms_key_id        = aws_kms_key.secondary.arn

  db_subnet_group_name            = aws_db_subnet_group.secondary.name
  vpc_security_group_ids          = [aws_security_group.secondary.id]
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.secondary.name

  iam_database_authentication_enabled = true
  deletion_protection                 = var.deletion_protection

  backup_retention_period      = var.backup_retention_days
  preferred_backup_window      = var.backup_window
  preferred_maintenance_window = var.maintenance_window
  copy_tags_to_snapshot        = true

  enabled_cloudwatch_logs_exports = ["postgresql"]

  skip_final_snapshot       = false
  final_snapshot_identifier = "${local.name}-${var.secondary_region}-final-${formatdate("YYYYMMDDhhmmss", timestamp())}"

  depends_on = [aws_rds_cluster_instance.primary]

  lifecycle {
    ignore_changes = [final_snapshot_identifier]
  }
}

resource "aws_rds_cluster_instance" "secondary" {
  provider = aws.secondary
  count    = var.instance_count

  identifier         = "${local.name}-${var.secondary_region}-${count.index + 1}"
  cluster_identifier = aws_rds_cluster.secondary.id

  engine         = aws_rds_cluster.secondary.engine
  engine_version = var.engine_version
  instance_class = var.instance_class

  promotion_tier             = count.index
  publicly_accessible        = false
  auto_minor_version_upgrade = true

  performance_insights_enabled    = true
  performance_insights_kms_key_id = aws_kms_key.secondary.arn

  monitoring_interval = 60
  monitoring_role_arn = aws_iam_role.monitoring.arn
}

# ---------------------------------------------------------------------------
# IAM database authentication: services connect with a short-lived token
# minted from their IAM role, so there are no static DB passwords for apps.
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "db_connect" {
  statement {
    sid     = "ConnectAsIamDatabaseUser"
    effect  = "Allow"
    actions = ["rds-db:connect"]

    resources = flatten([
      for user in var.iam_database_users : [
        "arn:${local.partition}:rds-db:${var.primary_region}:${local.account_id}:dbuser:${aws_rds_cluster.primary.cluster_resource_id}/${user}",
        "arn:${local.partition}:rds-db:${var.secondary_region}:${local.account_id}:dbuser:${aws_rds_cluster.secondary.cluster_resource_id}/${user}",
      ]
    ])
  }
}

resource "aws_iam_policy" "db_connect" {
  name        = "${local.name}-db-connect"
  description = "rds-db:connect for ${local.name} in both regions"
  policy      = data.aws_iam_policy_document.db_connect.json
}

resource "aws_iam_role_policy_attachment" "application" {
  for_each = toset(var.application_role_names)

  role       = each.value
  policy_arn = aws_iam_policy.db_connect.arn
}
