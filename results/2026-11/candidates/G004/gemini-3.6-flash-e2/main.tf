locals {
  db_name            = var.database_name != null ? var.database_name : replace(var.service_name, "-", "_")
  vpc_name           = var.vpc_name != null ? var.vpc_name : "apps-${var.environment}"
  param_group_family = "aurora-postgresql${split(".", var.engine_version)[0]}"

  common_tags = merge(
    {
      Service     = var.service_name
      Environment = var.environment
      ManagedBy   = "OpenTofu"
    },
    var.tags
  )
}

# --- Data Sources: Primary Region ---
data "aws_vpc" "primary" {
  filter {
    name   = "tag:Name"
    values = [local.vpc_name]
  }
}

data "aws_subnets" "primary_db" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.primary.id]
  }
  tags = {
    (var.subnet_tag_key) = var.subnet_tag_value
  }
}

# --- Data Sources: Secondary Region ---
data "aws_vpc" "secondary" {
  provider = aws.secondary
  filter {
    name   = "tag:Name"
    values = [local.vpc_name]
  }
}

data "aws_subnets" "secondary_db" {
  provider = aws.secondary
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.secondary.id]
  }
  tags = {
    (var.subnet_tag_key) = var.subnet_tag_value
  }
}

# --- DB Subnet Groups ---
resource "aws_db_subnet_group" "primary" {
  name        = "${var.service_name}-${var.environment}-primary"
  description = "Database subnet group for ${var.service_name} primary cluster in ${var.primary_region}"
  subnet_ids  = data.aws_subnets.primary_db.ids
  tags        = merge(local.common_tags, { Name = "${var.service_name}-${var.environment}-primary-subnet-group" })
}

resource "aws_db_subnet_group" "secondary" {
  provider    = aws.secondary
  name        = "${var.service_name}-${var.environment}-secondary"
  description = "Database subnet group for ${var.service_name} secondary cluster in ${var.secondary_region}"
  subnet_ids  = data.aws_subnets.secondary_db.ids
  tags        = merge(local.common_tags, { Name = "${var.service_name}-${var.environment}-secondary-subnet-group" })
}

# --- KMS Encryption Keys ---
resource "aws_kms_key" "primary" {
  description             = "KMS key for ${var.service_name} Aurora primary cluster in ${var.primary_region}"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  tags                    = merge(local.common_tags, { Name = "${var.service_name}-${var.environment}-primary-kms" })
}

resource "aws_kms_alias" "primary" {
  name          = "alias/${var.service_name}-${var.environment}-primary"
  target_key_id = aws_kms_key.primary.key_id
}

resource "aws_kms_key" "secondary" {
  provider                = aws.secondary
  description             = "KMS key for ${var.service_name} Aurora secondary cluster in ${var.secondary_region}"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  tags                    = merge(local.common_tags, { Name = "${var.service_name}-${var.environment}-secondary-kms" })
}

resource "aws_kms_alias" "secondary" {
  provider      = aws.secondary
  name          = "alias/${var.service_name}-${var.environment}-secondary"
  target_key_id = aws_kms_key.secondary.key_id
}

# --- Security Groups ---
resource "aws_security_group" "primary" {
  name        = "${var.service_name}-${var.environment}-primary-sg"
  description = "Security group for ${var.service_name} Aurora primary cluster"
  vpc_id      = data.aws_vpc.primary.id

  ingress {
    description     = "PostgreSQL access from primary VPC CIDR"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    cidr_blocks     = concat([data.aws_vpc.primary.cidr_block], var.allowed_cidr_blocks)
    security_groups = length(var.allowed_security_group_ids) > 0 ? var.allowed_security_group_ids : null
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "${var.service_name}-${var.environment}-primary-sg" })
}

resource "aws_security_group" "secondary" {
  provider    = aws.secondary
  name        = "${var.service_name}-${var.environment}-secondary-sg"
  description = "Security group for ${var.service_name} Aurora secondary cluster"
  vpc_id      = data.aws_vpc.secondary.id

  ingress {
    description     = "PostgreSQL access from secondary VPC CIDR"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    cidr_blocks     = concat([data.aws_vpc.secondary.cidr_block], var.allowed_cidr_blocks)
    security_groups = length(var.secondary_allowed_security_group_ids) > 0 ? var.secondary_allowed_security_group_ids : null
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "${var.service_name}-${var.environment}-secondary-sg" })
}

# --- Cluster Parameter Groups (Security & Encryption in Transit) ---
resource "aws_rds_cluster_parameter_group" "primary" {
  name        = "${var.service_name}-${var.environment}-primary-pg"
  family      = local.param_group_family
  description = "Cluster parameter group for ${var.service_name} primary cluster"

  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }

  parameter {
    name  = "log_statement"
    value = "ddl"
  }

  parameter {
    name  = "log_min_duration_statement"
    value = "1000"
  }

  tags = merge(local.common_tags, { Name = "${var.service_name}-${var.environment}-primary-pg" })
}

resource "aws_rds_cluster_parameter_group" "secondary" {
  provider    = aws.secondary
  name        = "${var.service_name}-${var.environment}-secondary-pg"
  family      = local.param_group_family
  description = "Cluster parameter group for ${var.service_name} secondary cluster"

  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }

  parameter {
    name  = "log_statement"
    value = "ddl"
  }

  parameter {
    name  = "log_min_duration_statement"
    value = "1000"
  }

  tags = merge(local.common_tags, { Name = "${var.service_name}-${var.environment}-secondary-pg" })
}

# --- Aurora Global Database Cluster ---
resource "aws_rds_global_cluster" "this" {
  global_cluster_identifier = "${var.service_name}-${var.environment}-global-db"
  engine                    = "aurora-postgresql"
  engine_version            = var.engine_version
  database_name             = local.db_name
  storage_encrypted         = true
  deletion_protection       = var.deletion_protection
}

# --- Primary Region Aurora Cluster ---
resource "aws_rds_cluster" "primary" {
  cluster_identifier                  = "${var.service_name}-${var.environment}-primary"
  global_cluster_identifier           = aws_rds_global_cluster.this.id
  engine                              = "aurora-postgresql"
  engine_version                      = var.engine_version
  database_name                       = local.db_name
  master_username                     = var.master_username
  manage_master_user_password         = true
  master_user_secret_kms_key_id       = aws_kms_key.primary.key_id
  db_subnet_group_name                = aws_db_subnet_group.primary.name
  vpc_security_group_ids              = [aws_security_group.primary.id]
  db_cluster_parameter_group_name     = aws_rds_cluster_parameter_group.primary.name
  kms_key_id                          = aws_kms_key.primary.arn
  storage_encrypted                   = true
  iam_database_authentication_enabled = true
  enabled_cloudwatch_logs_exports     = ["postgresql"]
  backup_retention_period             = var.backup_retention_period
  preferred_backup_window             = "03:00-04:00"
  preferred_maintenance_window        = "sun:04:30-sun:05:30"
  copy_tags_to_snapshot               = true
  deletion_protection                 = var.deletion_protection
  skip_final_snapshot                 = var.deletion_protection ? false : true
  final_snapshot_identifier           = "${var.service_name}-${var.environment}-primary-final-snapshot"

  tags = merge(local.common_tags, { Name = "${var.service_name}-${var.environment}-primary-cluster" })
}

resource "aws_rds_cluster_instance" "primary" {
  count                           = var.primary_instance_count
  identifier                      = "${var.service_name}-${var.environment}-primary-${count.index + 1}"
  cluster_identifier              = aws_rds_cluster.primary.id
  instance_class                  = var.instance_class
  engine                          = aws_rds_cluster.primary.engine
  engine_version                  = aws_rds_cluster.primary.engine_version
  publicly_accessible             = false
  auto_minor_version_upgrade      = true
  performance_insights_enabled    = true
  performance_insights_kms_key_id = aws_kms_key.primary.arn
  db_subnet_group_name            = aws_db_subnet_group.primary.name

  tags = merge(local.common_tags, { Name = "${var.service_name}-${var.environment}-primary-instance-${count.index + 1}" })
}

# --- Secondary Region Aurora Cluster ---
resource "aws_rds_cluster" "secondary" {
  provider                            = aws.secondary
  cluster_identifier                  = "${var.service_name}-${var.environment}-secondary"
  global_cluster_identifier           = aws_rds_global_cluster.this.id
  engine                              = "aurora-postgresql"
  engine_version                      = var.engine_version
  db_subnet_group_name                = aws_db_subnet_group.secondary.name
  vpc_security_group_ids              = [aws_security_group.secondary.id]
  db_cluster_parameter_group_name     = aws_rds_cluster_parameter_group.secondary.name
  kms_key_id                          = aws_kms_key.secondary.arn
  storage_encrypted                   = true
  iam_database_authentication_enabled = true
  enabled_cloudwatch_logs_exports     = ["postgresql"]
  backup_retention_period             = var.backup_retention_period
  preferred_backup_window             = "03:00-04:00"
  preferred_maintenance_window        = "sun:04:30-sun:05:30"
  copy_tags_to_snapshot               = true
  deletion_protection                 = var.deletion_protection
  skip_final_snapshot                 = var.deletion_protection ? false : true
  final_snapshot_identifier           = "${var.service_name}-${var.environment}-secondary-final-snapshot"

  depends_on = [
    aws_rds_cluster_instance.primary
  ]

  tags = merge(local.common_tags, { Name = "${var.service_name}-${var.environment}-secondary-cluster" })
}

resource "aws_rds_cluster_instance" "secondary" {
  provider                        = aws.secondary
  count                           = var.secondary_instance_count
  identifier                      = "${var.service_name}-${var.environment}-secondary-${count.index + 1}"
  cluster_identifier              = aws_rds_cluster.secondary.id
  instance_class                  = var.instance_class
  engine                          = aws_rds_cluster.secondary.engine
  engine_version                  = aws_rds_cluster.secondary.engine_version
  publicly_accessible             = false
  auto_minor_version_upgrade      = true
  performance_insights_enabled    = true
  performance_insights_kms_key_id = aws_kms_key.secondary.arn
  db_subnet_group_name            = aws_db_subnet_group.secondary.name

  tags = merge(local.common_tags, { Name = "${var.service_name}-${var.environment}-secondary-instance-${count.index + 1}" })
}
