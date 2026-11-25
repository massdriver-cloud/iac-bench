terraform {
  required_providers { aws = { source = "hashicorp/aws" } }
}
variable "name" { type = string }
variable "environment" { type = string }
variable "client_sg" { type = string }
variable "global_id" { type = string }
variable "primary" { type = bool }
variable "version_string" { type = string }
variable "class" { type = string }
variable "password" {
  type      = string
  sensitive = true
}
variable "tags" { type = map(string) }
variable "topic" { type = string }
variable "suffix" { type = string }
data "aws_vpc" "apps" {
  filter {
    name   = "tag:Name"
    values = ["apps-${var.environment}"]
  }
}
data "aws_subnets" "db" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.apps.id]
  }
  filter {
    name   = "tag:tier"
    values = ["database"]
  }
}
resource "aws_db_subnet_group" "db" {
  name       = var.name
  subnet_ids = data.aws_subnets.db.ids
  tags       = var.tags
}
resource "aws_security_group" "db" {
  name_prefix = "${var.name}-db-"
  description = "Private PostgreSQL access from service workloads"
  vpc_id      = data.aws_vpc.apps.id
  tags        = var.tags
}
resource "aws_vpc_security_group_ingress_rule" "postgres" {
  security_group_id            = aws_security_group.db.id
  referenced_security_group_id = var.client_sg
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
}
resource "aws_kms_key" "db" {
  description             = "Regional database encryption: ${var.name}"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  tags                    = var.tags
}
resource "aws_rds_cluster_parameter_group" "db" {
  name   = "${var.name}-pg16"
  family = "aurora-postgresql16"
  parameter {
    name         = "rds.force_ssl"
    value        = "1"
    apply_method = "pending-reboot"
  }
  tags = var.tags
}
resource "aws_cloudwatch_log_group" "postgres" {
  name              = "/aws/rds/cluster/${var.name}/postgresql"
  retention_in_days = 90
  tags              = var.tags
}
resource "aws_rds_cluster" "db" {
  cluster_identifier                  = var.name
  global_cluster_identifier           = var.global_id
  engine                              = "aurora-postgresql"
  engine_version                      = var.version_string
  master_username                     = var.primary ? "platform_admin" : null
  master_password                     = var.password
  database_name                       = var.primary ? "app" : null
  db_subnet_group_name                = aws_db_subnet_group.db.name
  db_cluster_parameter_group_name     = aws_rds_cluster_parameter_group.db.name
  vpc_security_group_ids              = [aws_security_group.db.id]
  storage_encrypted                   = true
  kms_key_id                          = aws_kms_key.db.arn
  iam_database_authentication_enabled = true
  backup_retention_period             = 35
  copy_tags_to_snapshot               = true
  deletion_protection                 = true
  skip_final_snapshot                 = false
  final_snapshot_identifier           = "${var.name}-final-${var.suffix}"
  enabled_cloudwatch_logs_exports     = ["postgresql"]
  depends_on                          = [aws_cloudwatch_log_group.postgres]
  tags                                = var.tags
}
resource "aws_rds_cluster_instance" "db" {
  count                           = 2
  identifier                      = "${var.name}-${count.index + 1}"
  cluster_identifier              = aws_rds_cluster.db.id
  engine                          = aws_rds_cluster.db.engine
  engine_version                  = var.version_string
  instance_class                  = var.class
  db_subnet_group_name            = aws_db_subnet_group.db.name
  publicly_accessible             = false
  auto_minor_version_upgrade      = false
  performance_insights_enabled    = true
  performance_insights_kms_key_id = aws_kms_key.db.arn
  tags                            = var.tags
}
output "resource_id" { value = aws_rds_cluster.db.cluster_resource_id }
output "endpoint" { value = aws_rds_cluster.db.endpoint }
output "cluster_id" { value = aws_rds_cluster.db.id }
