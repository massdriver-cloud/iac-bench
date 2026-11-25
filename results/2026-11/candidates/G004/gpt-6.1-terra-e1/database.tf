resource "aws_rds_global_cluster" "this" {
  global_cluster_identifier = local.name
  engine                    = "aurora-postgresql"
  engine_version            = var.engine_version
  database_name             = var.database_name
  storage_encrypted         = true
  deletion_protection       = true
}
resource "aws_rds_cluster_parameter_group" "primary" {
  name        = "${local.name}-primary-pg16"
  family      = "aurora-postgresql16"
  description = "Enforce encrypted connections"
  parameter {
    name         = "rds.force_ssl"
    value        = "1"
    apply_method = "pending-reboot"
  }
}
resource "aws_rds_cluster_parameter_group" "secondary" {
  provider    = aws.secondary
  name        = "${local.name}-secondary-pg16"
  family      = "aurora-postgresql16"
  description = "Enforce encrypted connections"
  parameter {
    name         = "rds.force_ssl"
    value        = "1"
    apply_method = "pending-reboot"
  }
}
resource "aws_cloudwatch_log_group" "primary" {
  name              = "/aws/rds/cluster/${local.name}-primary/postgresql"
  retention_in_days = 90
}
resource "aws_cloudwatch_log_group" "secondary" {
  provider          = aws.secondary
  name              = "/aws/rds/cluster/${local.name}-secondary/postgresql"
  retention_in_days = 90
}
resource "aws_rds_cluster" "primary" {
  cluster_identifier                  = "${local.name}-primary"
  global_cluster_identifier           = aws_rds_global_cluster.this.id
  engine                              = "aurora-postgresql"
  engine_version                      = var.engine_version
  master_username                     = var.master_username
  master_password                     = random_password.master.result
  db_subnet_group_name                = aws_db_subnet_group.primary.name
  vpc_security_group_ids              = [aws_security_group.primary.id]
  db_cluster_parameter_group_name     = aws_rds_cluster_parameter_group.primary.name
  storage_encrypted                   = true
  kms_key_id                          = aws_kms_key.primary.arn
  backup_retention_period             = 35
  preferred_backup_window             = "03:00-03:30"
  preferred_maintenance_window        = "sun:04:00-sun:04:30"
  deletion_protection                 = true
  skip_final_snapshot                 = false
  final_snapshot_identifier           = "${local.name}-primary-final"
  iam_database_authentication_enabled = true
  enabled_cloudwatch_logs_exports     = ["postgresql"]
  copy_tags_to_snapshot               = true
  depends_on                          = [aws_cloudwatch_log_group.primary]
}
resource "aws_rds_cluster_instance" "primary" {
  count                        = 2
  identifier                   = "${local.name}-primary-${count.index + 1}"
  cluster_identifier           = aws_rds_cluster.primary.id
  instance_class               = var.instance_class
  engine                       = aws_rds_cluster.primary.engine
  engine_version               = var.engine_version
  db_subnet_group_name         = aws_db_subnet_group.primary.name
  availability_zone            = sort(distinct([for s in data.aws_subnet.primary : s.availability_zone]))[count.index]
  publicly_accessible          = false
  auto_minor_version_upgrade   = false
  performance_insights_enabled = true
  promotion_tier               = count.index
}
resource "aws_rds_cluster" "secondary" {
  provider                            = aws.secondary
  cluster_identifier                  = "${local.name}-secondary"
  global_cluster_identifier           = aws_rds_global_cluster.this.id
  engine                              = "aurora-postgresql"
  engine_version                      = var.engine_version
  db_subnet_group_name                = aws_db_subnet_group.secondary.name
  vpc_security_group_ids              = [aws_security_group.secondary.id]
  db_cluster_parameter_group_name     = aws_rds_cluster_parameter_group.secondary.name
  storage_encrypted                   = true
  kms_key_id                          = aws_kms_key.secondary.arn
  deletion_protection                 = true
  skip_final_snapshot                 = false
  final_snapshot_identifier           = "${local.name}-secondary-final"
  iam_database_authentication_enabled = true
  enabled_cloudwatch_logs_exports     = ["postgresql"]
  copy_tags_to_snapshot               = true
  depends_on                          = [aws_rds_cluster_instance.primary, aws_cloudwatch_log_group.secondary]
}
resource "aws_rds_cluster_instance" "secondary" {
  provider                     = aws.secondary
  count                        = 2
  identifier                   = "${local.name}-secondary-${count.index + 1}"
  cluster_identifier           = aws_rds_cluster.secondary.id
  instance_class               = var.instance_class
  engine                       = aws_rds_cluster.secondary.engine
  engine_version               = var.engine_version
  db_subnet_group_name         = aws_db_subnet_group.secondary.name
  availability_zone            = sort(distinct([for s in data.aws_subnet.secondary : s.availability_zone]))[count.index]
  publicly_accessible          = false
  auto_minor_version_upgrade   = false
  performance_insights_enabled = true
  promotion_tier               = count.index
}
