resource "random_id" "snapshot" {
  byte_length = 4
}

resource "aws_rds_global_cluster" "this" {
  global_cluster_identifier = "${local.prefix}-global"
  engine                    = "aurora-postgresql"
  engine_version            = var.engine_version
  database_name             = var.database_name
  storage_encrypted         = true
  deletion_protection       = true
  force_destroy             = false
}

resource "aws_rds_cluster_parameter_group" "primary" {
  name_prefix = "${local.prefix}-primary-"
  family      = "aurora-postgresql16"
  description = "Require TLS for every PostgreSQL connection"
  parameter {
    name         = "rds.force_ssl"
    value        = "1"
    apply_method = "pending-reboot"
  }
  lifecycle { create_before_destroy = true }
}
resource "aws_rds_cluster_parameter_group" "secondary" {
  provider    = aws.secondary
  name_prefix = "${local.prefix}-secondary-"
  family      = "aurora-postgresql16"
  description = "Require TLS for every PostgreSQL connection, including after promotion"
  parameter {
    name         = "rds.force_ssl"
    value        = "1"
    apply_method = "pending-reboot"
  }
  lifecycle { create_before_destroy = true }
}

resource "aws_cloudwatch_log_group" "primary" {
  name              = "/aws/rds/cluster/${local.prefix}-primary/postgresql"
  retention_in_days = 90
  kms_key_id        = aws_kms_key.primary.arn
}
resource "aws_cloudwatch_log_group" "secondary" {
  provider          = aws.secondary
  name              = "/aws/rds/cluster/${local.prefix}-secondary/postgresql"
  retention_in_days = 90
  kms_key_id        = aws_kms_key.secondary.arn
}

resource "aws_rds_cluster" "primary" {
  cluster_identifier                  = "${local.prefix}-primary"
  global_cluster_identifier           = aws_rds_global_cluster.this.id
  engine                              = aws_rds_global_cluster.this.engine
  engine_version                      = var.engine_version
  database_name                       = var.database_name
  master_username                     = "cluster_admin"
  master_password                     = random_password.master.result
  port                                = 5432
  storage_encrypted                   = true
  kms_key_id                          = aws_kms_key.primary.arn
  db_subnet_group_name                = aws_db_subnet_group.primary.name
  vpc_security_group_ids              = [aws_security_group.primary.id]
  db_cluster_parameter_group_name     = aws_rds_cluster_parameter_group.primary.name
  iam_database_authentication_enabled = true
  backup_retention_period             = 35
  preferred_backup_window             = "06:00-07:00"
  preferred_maintenance_window        = "sun:08:00-sun:09:00"
  enabled_cloudwatch_logs_exports     = ["postgresql"]
  deletion_protection                 = true
  skip_final_snapshot                 = false
  final_snapshot_identifier           = "${local.prefix}-primary-final-${random_id.snapshot.hex}"
  copy_tags_to_snapshot               = true
  apply_immediately                   = false
  allow_major_version_upgrade         = false
  depends_on                          = [aws_cloudwatch_log_group.primary]
}

resource "aws_rds_cluster" "secondary" {
  provider                  = aws.secondary
  cluster_identifier        = "${local.prefix}-secondary"
  global_cluster_identifier = aws_rds_global_cluster.this.id
  engine                    = aws_rds_global_cluster.this.engine
  engine_version            = var.engine_version
  # No username/password/database on a global secondary: they replicate from the writer.
  source_region                       = var.primary_region
  port                                = 5432
  storage_encrypted                   = true
  kms_key_id                          = aws_kms_key.secondary.arn
  db_subnet_group_name                = aws_db_subnet_group.secondary.name
  vpc_security_group_ids              = [aws_security_group.secondary.id]
  db_cluster_parameter_group_name     = aws_rds_cluster_parameter_group.secondary.name
  iam_database_authentication_enabled = true
  backup_retention_period             = 35
  preferred_backup_window             = "07:00-08:00"
  preferred_maintenance_window        = "sun:09:00-sun:10:00"
  enabled_cloudwatch_logs_exports     = ["postgresql"]
  deletion_protection                 = true
  skip_final_snapshot                 = false
  final_snapshot_identifier           = "${local.prefix}-secondary-final-${random_id.snapshot.hex}"
  copy_tags_to_snapshot               = true
  apply_immediately                   = false
  allow_major_version_upgrade         = false
  # Create a live writer before adding a secondary to the global database.
  depends_on = [aws_rds_cluster_instance.primary, aws_cloudwatch_log_group.secondary]
}

resource "aws_rds_cluster_instance" "primary" {
  count                                 = var.instances_per_region
  identifier                            = "${local.prefix}-primary-${count.index + 1}"
  cluster_identifier                    = aws_rds_cluster.primary.id
  engine                                = aws_rds_cluster.primary.engine
  engine_version                        = var.engine_version
  instance_class                        = var.instance_class
  db_subnet_group_name                  = aws_db_subnet_group.primary.name
  availability_zone                     = local.primary_azs[count.index % max(1, length(local.primary_azs))]
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
  preferred_maintenance_window          = "sun:08:00-sun:09:00"
  ca_cert_identifier                    = "rds-ca-rsa2048-g1"
  depends_on                            = [aws_iam_role_policy_attachment.monitoring]
}
resource "aws_rds_cluster_instance" "secondary" {
  provider                              = aws.secondary
  count                                 = var.instances_per_region
  identifier                            = "${local.prefix}-secondary-${count.index + 1}"
  cluster_identifier                    = aws_rds_cluster.secondary.id
  engine                                = aws_rds_cluster.secondary.engine
  engine_version                        = var.engine_version
  instance_class                        = var.instance_class
  db_subnet_group_name                  = aws_db_subnet_group.secondary.name
  availability_zone                     = local.secondary_azs[count.index % max(1, length(local.secondary_azs))]
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
  preferred_maintenance_window          = "sun:09:00-sun:10:00"
  ca_cert_identifier                    = "rds-ca-rsa2048-g1"
  depends_on                            = [aws_iam_role_policy_attachment.monitoring]
}
