locals {
  prefix = "${var.name}-${var.environment}"
  tags = merge(var.tags, {
    Service = var.name, Environment = var.environment, ManagedBy = "OpenTofu", DataClassification = "confidential"
  })
  parameters = {
    "rds.force_ssl"            = { value = "1", method = "immediate" }
    "shared_preload_libraries" = { value = "pg_stat_statements,pgaudit", method = "pending-reboot" }
    "pgaudit.log"              = { value = "ddl,role", method = "immediate" }
    "pgaudit.log_parameter"    = { value = "0", method = "immediate" }
    "log_connections"          = { value = "1", method = "immediate" }
    "log_disconnections"       = { value = "1", method = "immediate" }
    "log_statement"            = { value = "none", method = "immediate" }
    "log_min_error_statement"  = { value = "panic", method = "immediate" }
  }
}

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_vpc" "primary" {
  tags = { Name = var.environment }
}
data "aws_vpc" "secondary" {
  provider = aws.secondary
  tags     = { Name = var.environment }
}
data "aws_subnets" "primary" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.primary.id]
  }
  tags = { tier = "database" }
}
data "aws_subnets" "secondary" {
  provider = aws.secondary
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.secondary.id]
  }
  tags = { tier = "database" }
}
data "aws_subnet" "primary" {
  for_each = toset(data.aws_subnets.primary.ids)
  id       = each.value
}
data "aws_subnet" "secondary" {
  provider = aws.secondary
  for_each = toset(data.aws_subnets.secondary.ids)
  id       = each.value
}
locals {
  primary_azs   = sort(distinct([for s in data.aws_subnet.primary : s.availability_zone]))
  secondary_azs = sort(distinct([for s in data.aws_subnet.secondary : s.availability_zone]))
}
resource "aws_db_subnet_group" "primary" {
  name       = "${local.prefix}-primary"
  subnet_ids = data.aws_subnets.primary.ids
  lifecycle {
    precondition {
      condition     = length(local.primary_azs) >= 2 && alltrue([for s in data.aws_subnet.primary : !s.map_public_ip_on_launch])
      error_message = "Primary VPC needs private tier=database subnets in at least two AZs. Verify their route tables have no Internet Gateway route."
    }
  }
}
resource "aws_db_subnet_group" "secondary" {
  provider   = aws.secondary
  name       = "${local.prefix}-secondary"
  subnet_ids = data.aws_subnets.secondary.ids
  lifecycle {
    precondition {
      condition     = length(local.secondary_azs) >= 2 && alltrue([for s in data.aws_subnet.secondary : !s.map_public_ip_on_launch])
      error_message = "Secondary VPC needs private tier=database subnets in at least two AZs. Verify their route tables have no Internet Gateway route."
    }
  }
}
resource "aws_security_group" "primary" {
  name_prefix = "${local.prefix}-db-"
  description = "Private Aurora: only explicitly authorized application groups"
  vpc_id      = data.aws_vpc.primary.id
}
resource "aws_security_group" "secondary" {
  provider    = aws.secondary
  name_prefix = "${local.prefix}-db-"
  description = "Private Aurora DR: only explicitly authorized application groups"
  vpc_id      = data.aws_vpc.secondary.id
}
resource "aws_vpc_security_group_ingress_rule" "primary" {
  for_each                     = var.client_security_group_ids.primary
  security_group_id            = aws_security_group.primary.id
  referenced_security_group_id = each.value
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
}
resource "aws_vpc_security_group_ingress_rule" "secondary" {
  provider                     = aws.secondary
  for_each                     = var.client_security_group_ids.secondary
  security_group_id            = aws_security_group.secondary.id
  referenced_security_group_id = each.value
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
}

# Independent regional keys avoid a dependency on the failed region's KMS endpoint.
# Protect data keys from accidental destruction even when a cluster destroy fails.
resource "aws_kms_key" "primary" {
  description             = "${local.prefix} regional database, backup and secret encryption"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  lifecycle { prevent_destroy = true }
}
resource "aws_kms_key" "secondary" {
  provider                = aws.secondary
  description             = "${local.prefix} DR database, backup and secret encryption"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  lifecycle { prevent_destroy = true }
}
resource "aws_kms_alias" "primary" {
  name          = "alias/${local.prefix}-database"
  target_key_id = aws_kms_key.primary.key_id
}
resource "aws_kms_alias" "secondary" {
  provider      = aws.secondary
  name          = "alias/${local.prefix}-database"
  target_key_id = aws_kms_key.secondary.key_id
}
resource "aws_rds_cluster_parameter_group" "primary" {
  name_prefix = "${local.prefix}-"
  family      = "aurora-postgresql16"
  dynamic "parameter" {
    for_each = local.parameters
    content {
      name         = parameter.key
      value        = parameter.value.value
      apply_method = parameter.value.method
    }
  }
  lifecycle { create_before_destroy = true }
}
resource "aws_rds_cluster_parameter_group" "secondary" {
  provider    = aws.secondary
  name_prefix = "${local.prefix}-"
  family      = "aurora-postgresql16"
  dynamic "parameter" {
    for_each = local.parameters
    content {
      name         = parameter.key
      value        = parameter.value.value
      apply_method = parameter.value.method
    }
  }
  lifecycle { create_before_destroy = true }
}
resource "random_password" "master" {
  length           = 40
  special          = true
  override_special = "!#$%&*+-=?_"
}
resource "aws_secretsmanager_secret" "admin" {
  name                    = "${local.prefix}/database-admin"
  description             = "Break-glass bootstrap only; applications use IAM authentication"
  kms_key_id              = aws_kms_key.primary.arn
  recovery_window_in_days = 30
  replica {
    region     = var.secondary_region
    kms_key_id = aws_kms_key.secondary.arn
  }
}
resource "aws_secretsmanager_secret_version" "admin" {
  secret_id = aws_secretsmanager_secret.admin.id
  secret_string = jsonencode({
    username = "dbadmin", password = random_password.master.result, port = 5432, engine = "postgres", dbname = "app"
  })
}
resource "aws_rds_global_cluster" "this" {
  global_cluster_identifier = local.prefix
  engine                    = "aurora-postgresql"
  engine_version            = var.engine_version
  database_name             = "app"
  storage_encrypted         = true
  deletion_protection       = true
}
resource "aws_rds_cluster" "primary" {
  cluster_identifier                  = "${local.prefix}-primary"
  global_cluster_identifier           = aws_rds_global_cluster.this.id
  engine                              = aws_rds_global_cluster.this.engine
  engine_version                      = var.engine_version
  master_username                     = "dbadmin"
  master_password                     = random_password.master.result
  database_name                       = "app"
  port                                = 5432
  storage_encrypted                   = true
  kms_key_id                          = aws_kms_key.primary.arn
  db_subnet_group_name                = aws_db_subnet_group.primary.name
  vpc_security_group_ids              = [aws_security_group.primary.id]
  db_cluster_parameter_group_name     = aws_rds_cluster_parameter_group.primary.name
  iam_database_authentication_enabled = true
  backup_retention_period             = 35
  preferred_backup_window             = "07:00-08:00"
  preferred_maintenance_window        = "sun:09:00-sun:10:00"
  enabled_cloudwatch_logs_exports     = ["postgresql"]
  deletion_protection                 = true
  skip_final_snapshot                 = false
  final_snapshot_identifier           = "${local.prefix}-primary-final"
  copy_tags_to_snapshot               = true
  apply_immediately                   = false
  allow_major_version_upgrade         = false
  depends_on                          = [aws_cloudwatch_log_group.primary]
}
resource "aws_rds_cluster" "secondary" {
  provider                            = aws.secondary
  cluster_identifier                  = "${local.prefix}-secondary"
  global_cluster_identifier           = aws_rds_global_cluster.this.id
  engine                              = aws_rds_global_cluster.this.engine
  engine_version                      = var.engine_version
  source_region                       = var.primary_region
  port                                = 5432
  storage_encrypted                   = true
  kms_key_id                          = aws_kms_key.secondary.arn
  db_subnet_group_name                = aws_db_subnet_group.secondary.name
  vpc_security_group_ids              = [aws_security_group.secondary.id]
  db_cluster_parameter_group_name     = aws_rds_cluster_parameter_group.secondary.name
  iam_database_authentication_enabled = true
  backup_retention_period             = 35
  preferred_backup_window             = "08:00-09:00"
  preferred_maintenance_window        = "sun:10:00-sun:11:00"
  enabled_cloudwatch_logs_exports     = ["postgresql"]
  deletion_protection                 = true
  skip_final_snapshot                 = false
  final_snapshot_identifier           = "${local.prefix}-secondary-final"
  copy_tags_to_snapshot               = true
  apply_immediately                   = false
  allow_major_version_upgrade         = false
  depends_on                          = [aws_rds_cluster_instance.primary, aws_cloudwatch_log_group.secondary]
}
resource "aws_rds_cluster_instance" "primary" {
  count                                 = 2
  identifier                            = "${local.prefix}-primary-${count.index + 1}"
  cluster_identifier                    = aws_rds_cluster.primary.id
  engine                                = aws_rds_cluster.primary.engine
  engine_version                        = var.engine_version
  instance_class                        = var.instance_class
  availability_zone                     = local.primary_azs[count.index]
  db_subnet_group_name                  = aws_db_subnet_group.primary.name
  publicly_accessible                   = false
  auto_minor_version_upgrade            = false
  promotion_tier                        = count.index
  monitoring_interval                   = 60
  monitoring_role_arn                   = aws_iam_role.monitoring.arn
  performance_insights_enabled          = true
  performance_insights_kms_key_id       = aws_kms_key.primary.arn
  performance_insights_retention_period = 7
  copy_tags_to_snapshot                 = true
  apply_immediately                     = false
  depends_on                            = [aws_iam_role_policy_attachment.monitoring]
}
resource "aws_rds_cluster_instance" "secondary" {
  provider                              = aws.secondary
  count                                 = 2
  identifier                            = "${local.prefix}-secondary-${count.index + 1}"
  cluster_identifier                    = aws_rds_cluster.secondary.id
  engine                                = aws_rds_cluster.secondary.engine
  engine_version                        = var.engine_version
  instance_class                        = var.instance_class
  availability_zone                     = local.secondary_azs[count.index]
  db_subnet_group_name                  = aws_db_subnet_group.secondary.name
  publicly_accessible                   = false
  auto_minor_version_upgrade            = false
  promotion_tier                        = count.index
  monitoring_interval                   = 60
  monitoring_role_arn                   = aws_iam_role.monitoring.arn
  performance_insights_enabled          = true
  performance_insights_kms_key_id       = aws_kms_key.secondary.arn
  performance_insights_retention_period = 7
  copy_tags_to_snapshot                 = true
  apply_immediately                     = false
  depends_on                            = [aws_iam_role_policy_attachment.monitoring]
}
