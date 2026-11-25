terraform {
  required_providers {
    aws = { source = "hashicorp/aws" }
  }
}
variable "name" { type = string }
variable "environment" { type = string }
variable "database" { type = string }
variable "client_group" { type = string }
variable "global_id" { type = string }
variable "engine_version" { type = string }
variable "instance_class" { type = string }
variable "source_region" {
  type    = string
  default = null
}
variable "password_version" {
  type    = number
  default = null
}
variable "password" {
  type      = string
  sensitive = true
  ephemeral = true
  default   = null
}
data "aws_vpc" "apps" {
  tags = { Name = "apps-${var.environment}" }
}
data "aws_subnets" "database" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.apps.id]
  }
  tags = { tier = "database" }
}
data "aws_subnet" "selected" {
  for_each = toset(data.aws_subnets.database.ids)
  id       = each.value
}
locals {
  azs = sort(distinct([for subnet in data.aws_subnet.selected : subnet.availability_zone]))
}
resource "aws_db_subnet_group" "db" {
  name       = var.name
  subnet_ids = data.aws_subnets.database.ids
  lifecycle {
    precondition {
      condition     = length(local.azs) >= 2
      error_message = "The database subnets must span at least two AZs."
    }
  }
}
resource "aws_security_group" "db" {
  name_prefix = "${var.name}-"
  description = "Private Aurora access for ${var.name}"
  vpc_id      = data.aws_vpc.apps.id
}
resource "aws_vpc_security_group_ingress_rule" "postgres" {
  security_group_id            = aws_security_group.db.id
  referenced_security_group_id = var.client_group
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
}
resource "aws_rds_cluster_parameter_group" "pg" {
  name   = var.name
  family = "aurora-postgresql16"
  parameter {
    name         = "rds.force_ssl"
    value        = "1"
    apply_method = "pending-reboot"
  }
}
resource "aws_cloudwatch_log_group" "postgres" {
  name              = "/aws/rds/cluster/${var.name}/postgresql"
  retention_in_days = 90
}
resource "aws_kms_key" "db" {
  description             = "Aurora and snapshot encryption for ${var.name}"
  enable_key_rotation     = true
  deletion_window_in_days = 30
}
resource "aws_rds_cluster" "db" {
  cluster_identifier                  = var.name
  engine                              = "aurora-postgresql"
  engine_version                      = var.engine_version
  global_cluster_identifier           = var.global_id
  source_region                       = var.source_region
  database_name                       = var.source_region == null ? var.database : null
  master_username                     = var.source_region == null ? "clusteradmin" : null
  master_password_wo                  = var.password
  master_password_wo_version          = var.password_version
  port                                = 5432
  db_subnet_group_name                = aws_db_subnet_group.db.name
  vpc_security_group_ids              = [aws_security_group.db.id]
  db_cluster_parameter_group_name     = aws_rds_cluster_parameter_group.pg.name
  storage_encrypted                   = true
  kms_key_id                          = aws_kms_key.db.arn
  iam_database_authentication_enabled = true
  enabled_cloudwatch_logs_exports     = ["postgresql"]
  backup_retention_period             = 35
  copy_tags_to_snapshot               = true
  deletion_protection                 = true
  skip_final_snapshot                 = false
  final_snapshot_identifier           = "${var.name}-final"
  depends_on                          = [aws_cloudwatch_log_group.postgres]
}
resource "aws_rds_cluster_instance" "db" {
  count                        = 2
  identifier                   = "${var.name}-${count.index + 1}"
  cluster_identifier           = aws_rds_cluster.db.id
  engine                       = aws_rds_cluster.db.engine
  engine_version               = var.engine_version
  instance_class               = var.instance_class
  availability_zone            = local.azs[count.index]
  db_subnet_group_name         = aws_db_subnet_group.db.name
  publicly_accessible          = false
  auto_minor_version_upgrade   = false
  performance_insights_enabled = true
}
output "resource_id" { value = aws_rds_cluster.db.cluster_resource_id }
output "endpoint" { value = aws_rds_cluster.db.endpoint }
output "ready_global_id" {
  value      = aws_rds_cluster.db.global_cluster_identifier
  depends_on = [aws_rds_cluster_instance.db]
}
