data "aws_caller_identity" "current" {}

locals {
  identifier    = "${var.name}-${var.environment}"
  vpc_name      = "apps-${var.environment}"
  major_version = split(".", var.engine_version)[0]
  pg_family     = "aurora-postgresql${local.major_version}"

  tags = merge(var.tags, {
    Service     = var.name
    Environment = var.environment
    ManagedBy   = "opentofu"
    DataClass   = "customer-payment"
  })

  primary_clients   = toset(var.client_security_group_ids)
  secondary_clients = toset(var.secondary_client_security_group_ids)
}

###############################################################################
# Network lookups (VPCs and database subnets are owned by the network team)
###############################################################################

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
  tags = {
    tier = "database"
  }
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
  tags = {
    tier = "database"
  }
}

resource "aws_db_subnet_group" "primary" {
  name       = local.identifier
  subnet_ids = data.aws_subnets.primary.ids
}

resource "aws_db_subnet_group" "secondary" {
  provider = aws.secondary

  name       = local.identifier
  subnet_ids = data.aws_subnets.secondary.ids
}

###############################################################################
# Security groups: only explicitly listed client groups may reach 5432
###############################################################################

resource "aws_security_group" "primary" {
  name_prefix = "${local.identifier}-db-"
  description = "Aurora PostgreSQL ${local.identifier}"
  vpc_id      = data.aws_vpc.primary.id

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "primary" {
  for_each = local.primary_clients

  security_group_id            = aws_security_group.primary.id
  referenced_security_group_id = each.value
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  description                  = "PostgreSQL from client security group"
}

resource "aws_security_group" "secondary" {
  provider = aws.secondary

  name_prefix = "${local.identifier}-db-"
  description = "Aurora PostgreSQL ${local.identifier}"
  vpc_id      = data.aws_vpc.secondary.id

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "secondary" {
  for_each = local.secondary_clients
  provider = aws.secondary

  security_group_id            = aws_security_group.secondary.id
  referenced_security_group_id = each.value
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  description                  = "PostgreSQL from client security group"
}

###############################################################################
# Encryption keys (one customer-managed key per region)
###############################################################################

resource "aws_kms_key" "primary" {
  description             = "Aurora ${local.identifier} (${var.primary_region})"
  enable_key_rotation     = true
  deletion_window_in_days = 30
}

resource "aws_kms_alias" "primary" {
  name          = "alias/${local.identifier}-aurora"
  target_key_id = aws_kms_key.primary.key_id
}

resource "aws_kms_key" "secondary" {
  provider = aws.secondary

  description             = "Aurora ${local.identifier} (${var.secondary_region})"
  enable_key_rotation     = true
  deletion_window_in_days = 30
}

resource "aws_kms_alias" "secondary" {
  provider = aws.secondary

  name          = "alias/${local.identifier}-aurora"
  target_key_id = aws_kms_key.secondary.key_id
}

###############################################################################
# Cluster parameter groups: TLS required, auditing enabled
###############################################################################

resource "aws_rds_cluster_parameter_group" "primary" {
  name_prefix = "${local.identifier}-"
  family      = local.pg_family
  description = "Aurora ${local.identifier}"

  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }
  parameter {
    name         = "shared_preload_libraries"
    value        = "pg_stat_statements,pgaudit"
    apply_method = "pending-reboot"
  }
  parameter {
    name  = "pgaudit.log"
    value = "ddl,role"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_rds_cluster_parameter_group" "secondary" {
  provider = aws.secondary

  name_prefix = "${local.identifier}-"
  family      = local.pg_family
  description = "Aurora ${local.identifier}"

  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }
  parameter {
    name         = "shared_preload_libraries"
    value        = "pg_stat_statements,pgaudit"
    apply_method = "pending-reboot"
  }
  parameter {
    name  = "pgaudit.log"
    value = "ddl,role"
  }

  lifecycle {
    create_before_destroy = true
  }
}

###############################################################################
# Enhanced monitoring role (IAM is global, shared by both regions)
###############################################################################

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
  name               = "${local.identifier}-rds-monitoring"
  assume_role_policy = data.aws_iam_policy_document.monitoring_assume.json
}

resource "aws_iam_role_policy_attachment" "monitoring" {
  role       = aws_iam_role.monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRolePolicy"
}

###############################################################################
# Aurora Global Database: primary cluster + cross-region secondary cluster
###############################################################################

resource "aws_rds_global_cluster" "this" {
  global_cluster_identifier = local.identifier
  engine                    = "aurora-postgresql"
  engine_version            = var.engine_version
  database_name             = var.database_name
  storage_encrypted         = true
  deletion_protection       = var.deletion_protection
}

resource "aws_rds_cluster" "primary" {
  cluster_identifier        = "${local.identifier}-${var.primary_region}"
  global_cluster_identifier = aws_rds_global_cluster.this.id
  engine                    = aws_rds_global_cluster.this.engine
  engine_version            = aws_rds_global_cluster.this.engine_version
  database_name             = var.database_name

  master_username               = var.master_username
  manage_master_user_password   = true
  master_user_secret_kms_key_id = aws_kms_key.primary.arn

  db_subnet_group_name            = aws_db_subnet_group.primary.name
  vpc_security_group_ids          = [aws_security_group.primary.id]
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.primary.name
  port                            = 5432

  storage_encrypted                   = true
  kms_key_id                          = aws_kms_key.primary.arn
  iam_database_authentication_enabled = true

  backup_retention_period      = var.backup_retention_days
  preferred_backup_window      = "03:00-04:00"
  preferred_maintenance_window = "sun:05:00-sun:06:00"
  copy_tags_to_snapshot        = true
  skip_final_snapshot          = var.skip_final_snapshot
  final_snapshot_identifier    = var.skip_final_snapshot ? null : "${local.identifier}-${var.primary_region}-final"
  deletion_protection          = var.deletion_protection

  enabled_cloudwatch_logs_exports = ["postgresql"]

  lifecycle {
    # Failover/switchover moves the writer between regions; never fight it.
    ignore_changes = [global_cluster_identifier, master_username]
  }
}

resource "aws_rds_cluster_instance" "primary" {
  count = var.primary_instance_count

  identifier           = "${local.identifier}-${var.primary_region}-${count.index + 1}"
  cluster_identifier   = aws_rds_cluster.primary.id
  engine               = aws_rds_cluster.primary.engine
  engine_version       = aws_rds_cluster.primary.engine_version
  instance_class       = var.instance_class
  db_subnet_group_name = aws_db_subnet_group.primary.name
  promotion_tier       = count.index == 0 ? 0 : 1

  publicly_accessible        = false
  auto_minor_version_upgrade = false
  copy_tags_to_snapshot      = true

  monitoring_interval             = 60
  monitoring_role_arn             = aws_iam_role.monitoring.arn
  performance_insights_enabled    = true
  performance_insights_kms_key_id = aws_kms_key.primary.arn
}

resource "aws_rds_cluster" "secondary" {
  provider = aws.secondary

  cluster_identifier        = "${local.identifier}-${var.secondary_region}"
  global_cluster_identifier = aws_rds_global_cluster.this.id
  engine                    = aws_rds_global_cluster.this.engine
  engine_version            = aws_rds_global_cluster.this.engine_version
  source_region             = var.primary_region

  db_subnet_group_name            = aws_db_subnet_group.secondary.name
  vpc_security_group_ids          = [aws_security_group.secondary.id]
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.secondary.name
  port                            = 5432

  storage_encrypted                   = true
  kms_key_id                          = aws_kms_key.secondary.arn
  iam_database_authentication_enabled = true

  backup_retention_period      = var.backup_retention_days
  preferred_backup_window      = "03:00-04:00"
  preferred_maintenance_window = "sun:05:00-sun:06:00"
  copy_tags_to_snapshot        = true
  skip_final_snapshot          = var.skip_final_snapshot
  final_snapshot_identifier    = var.skip_final_snapshot ? null : "${local.identifier}-${var.secondary_region}-final"
  deletion_protection          = var.deletion_protection

  enabled_cloudwatch_logs_exports = ["postgresql"]

  lifecycle {
    ignore_changes = [global_cluster_identifier, master_username]
  }

  # The secondary can only join once the primary has a writer instance.
  depends_on = [aws_rds_cluster_instance.primary]
}

resource "aws_rds_cluster_instance" "secondary" {
  provider = aws.secondary
  count    = var.secondary_instance_count

  identifier           = "${local.identifier}-${var.secondary_region}-${count.index + 1}"
  cluster_identifier   = aws_rds_cluster.secondary.id
  engine               = aws_rds_cluster.secondary.engine
  engine_version       = aws_rds_cluster.secondary.engine_version
  instance_class       = var.instance_class
  db_subnet_group_name = aws_db_subnet_group.secondary.name
  promotion_tier       = count.index == 0 ? 0 : 1

  publicly_accessible        = false
  auto_minor_version_upgrade = false
  copy_tags_to_snapshot      = true

  monitoring_interval             = 60
  monitoring_role_arn             = aws_iam_role.monitoring.arn
  performance_insights_enabled    = true
  performance_insights_kms_key_id = aws_kms_key.secondary.arn
}
