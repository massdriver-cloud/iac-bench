data "aws_vpc" "primary" {
  tags = {
    Name = "apps-${var.environment}"
  }
}

data "aws_subnets" "primary" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.primary.id]
  }

  tags = {
    tier = "database"
  }
}

data "aws_vpc" "secondary" {
  provider = aws.secondary

  tags = {
    Name = "apps-${var.environment}"
  }
}

data "aws_subnets" "secondary" {
  provider = aws.secondary

  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.secondary.id]
  }

  tags = {
    tier = "database"
  }
}

resource "aws_db_subnet_group" "primary" {
  name        = "${var.service_name}-${var.environment}-primary"
  description = "Primary DB subnet group for ${var.service_name} ${var.environment}"
  subnet_ids  = data.aws_subnets.primary.ids

  tags = {
    Name        = "${var.service_name}-${var.environment}-primary"
    Environment = var.environment
    Service     = var.service_name
  }
}

resource "aws_db_subnet_group" "secondary" {
  provider = aws.secondary

  name        = "${var.service_name}-${var.environment}-secondary"
  description = "Secondary DB subnet group for ${var.service_name} ${var.environment}"
  subnet_ids  = data.aws_subnets.secondary.ids

  tags = {
    Name        = "${var.service_name}-${var.environment}-secondary"
    Environment = var.environment
    Service     = var.service_name
  }
}

resource "aws_kms_key" "primary" {
  description             = "KMS key for Aurora PostgreSQL cluster ${var.service_name}-${var.environment} (Primary)"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = {
    Name        = "${var.service_name}-${var.environment}-primary-db-key"
    Environment = var.environment
    Service     = var.service_name
  }
}

resource "aws_kms_key" "secondary" {
  provider = aws.secondary

  description             = "KMS key for Aurora PostgreSQL cluster ${var.service_name}-${var.environment} (Secondary)"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = {
    Name        = "${var.service_name}-${var.environment}-secondary-db-key"
    Environment = var.environment
    Service     = var.service_name
  }
}

resource "random_password" "master_password" {
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "aws_rds_global_cluster" "this" {
  global_cluster_identifier = "${var.service_name}-${var.environment}-global"
  engine                    = "aurora-postgresql"
  engine_version            = var.engine_version
  database_name             = var.db_name
  storage_encrypted         = true
}

resource "aws_rds_cluster" "primary" {
  cluster_identifier                  = "${var.service_name}-${var.environment}-primary"
  global_cluster_identifier           = aws_rds_global_cluster.this.id
  engine                              = aws_rds_global_cluster.this.engine
  engine_version                      = aws_rds_global_cluster.this.engine_version
  database_name                       = var.db_name
  master_username                     = "postgres"
  master_password                     = random_password.master_password.result
  db_subnet_group_name                = aws_db_subnet_group.primary.name
  kms_key_id                          = aws_kms_key.primary.arn
  storage_encrypted                   = true
  iam_database_authentication_enabled = true
  backup_retention_period             = var.backup_retention_period
  preferred_backup_window             = "07:00-09:00"
  skip_final_snapshot                 = var.skip_final_snapshot
  final_snapshot_identifier           = "${var.service_name}-${var.environment}-primary-final-snapshot"

  tags = {
    Name        = "${var.service_name}-${var.environment}-primary"
    Environment = var.environment
    Service     = var.service_name
  }
}

resource "aws_rds_cluster_instance" "primary" {
  count = var.primary_instance_count

  identifier                      = "${var.service_name}-${var.environment}-primary-${count.index + 1}"
  cluster_identifier              = aws_rds_cluster.primary.id
  engine                          = aws_rds_cluster.primary.engine
  engine_version                  = aws_rds_cluster.primary.engine_version
  instance_class                  = var.instance_class
  db_subnet_group_name            = aws_db_subnet_group.primary.name
  performance_insights_enabled    = true
  performance_insights_kms_key_id = aws_kms_key.primary.arn

  tags = {
    Name        = "${var.service_name}-${var.environment}-primary-${count.index + 1}"
    Environment = var.environment
    Service     = var.service_name
  }
}

resource "aws_rds_cluster" "secondary" {
  provider = aws.secondary

  cluster_identifier                  = "${var.service_name}-${var.environment}-secondary"
  global_cluster_identifier           = aws_rds_global_cluster.this.id
  engine                              = aws_rds_global_cluster.this.engine
  engine_version                      = aws_rds_global_cluster.this.engine_version
  db_subnet_group_name                = aws_db_subnet_group.secondary.name
  kms_key_id                          = aws_kms_key.secondary.arn
  storage_encrypted                   = true
  iam_database_authentication_enabled = true
  skip_final_snapshot                 = var.skip_final_snapshot
  final_snapshot_identifier           = "${var.service_name}-${var.environment}-secondary-final-snapshot"

  depends_on = [
    aws_rds_cluster_instance.primary
  ]

  tags = {
    Name        = "${var.service_name}-${var.environment}-secondary"
    Environment = var.environment
    Service     = var.service_name
  }
}

resource "aws_rds_cluster_instance" "secondary" {
  provider = aws.secondary
  count    = var.secondary_instance_count

  identifier                      = "${var.service_name}-${var.environment}-secondary-${count.index + 1}"
  cluster_identifier              = aws_rds_cluster.secondary.id
  engine                          = aws_rds_cluster.secondary.engine
  engine_version                  = aws_rds_cluster.secondary.engine_version
  instance_class                  = var.instance_class
  db_subnet_group_name            = aws_db_subnet_group.secondary.name
  performance_insights_enabled    = true
  performance_insights_kms_key_id = aws_kms_key.secondary.arn

  tags = {
    Name        = "${var.service_name}-${var.environment}-secondary-${count.index + 1}"
    Environment = var.environment
    Service     = var.service_name
  }
}
