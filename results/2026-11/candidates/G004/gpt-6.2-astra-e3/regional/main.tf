terraform {
  required_providers { aws = { source = "hashicorp/aws" } }
}
variable "name" { type = string }
variable "environment" { type = string }
variable "site" { type = object({ region = string, client_sg = string, alarm_topic = string }) }
variable "global_id" { type = string }
variable "engine_version" { type = string }
variable "instance_class" { type = string }
variable "primary" { type = bool }
variable "password" {
  type      = string
  sensitive = true
  default   = null
}
variable "source_region" {
  type    = string
  default = null
}
variable "snapshot_suffix" { type = string }
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
data "aws_subnet" "db" {
  for_each = toset(data.aws_subnets.db.ids)
  id       = each.key
}
locals {
  id    = "${var.name}-${var.site.region}"
  zones = sort(distinct([for s in data.aws_subnet.db : s.availability_zone]))
}
resource "aws_db_subnet_group" "db" {
  name       = var.name
  subnet_ids = data.aws_subnets.db.ids
  lifecycle {
    precondition {
      condition     = length(local.zones) >= 2
      error_message = "Database subnets must span at least two availability zones."
    }
  }
}
resource "aws_security_group" "db" {
  name_prefix = "${var.name}-db-"
  description = "Private Aurora PostgreSQL"
  vpc_id      = data.aws_vpc.apps.id
}
resource "aws_vpc_security_group_ingress_rule" "app" {
  security_group_id            = aws_security_group.db.id
  referenced_security_group_id = var.site.client_sg
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
}
resource "aws_kms_key" "db" {
  description             = "${var.name} regional Aurora encryption"
  enable_key_rotation     = true
  deletion_window_in_days = 30
}
resource "aws_rds_cluster_parameter_group" "db" {
  name_prefix = "${var.name}-"
  family      = "aurora-postgresql16"
  parameter {
    name         = "rds.force_ssl"
    value        = "1"
    apply_method = "pending-reboot"
  }
  lifecycle { create_before_destroy = true }
}
resource "aws_cloudwatch_log_group" "db" {
  name              = "/aws/rds/cluster/${local.id}/postgresql"
  retention_in_days = 90
}
resource "aws_rds_cluster" "db" {
  cluster_identifier                  = local.id
  database_name                       = var.primary ? "app" : null
  global_cluster_identifier           = var.global_id
  engine                              = "aurora-postgresql"
  engine_version                      = var.engine_version
  master_username                     = var.primary ? "dbadmin" : null
  master_password                     = var.password
  source_region                       = var.source_region
  iam_database_authentication_enabled = true
  storage_encrypted                   = true
  kms_key_id                          = aws_kms_key.db.arn
  db_subnet_group_name                = aws_db_subnet_group.db.name
  vpc_security_group_ids              = [aws_security_group.db.id]
  db_cluster_parameter_group_name     = aws_rds_cluster_parameter_group.db.name
  enabled_cloudwatch_logs_exports     = ["postgresql"]
  backup_retention_period             = 35
  preferred_backup_window             = "05:00-05:30"
  preferred_maintenance_window        = "sun:06:00-sun:07:00"
  copy_tags_to_snapshot               = true
  deletion_protection                 = true
  skip_final_snapshot                 = false
  final_snapshot_identifier           = "${local.id}-final-${var.snapshot_suffix}"
  depends_on                          = [aws_cloudwatch_log_group.db]
}
resource "aws_rds_cluster_instance" "db" {
  count                           = 2
  identifier                      = "${local.id}-${count.index + 1}"
  cluster_identifier              = aws_rds_cluster.db.id
  engine                          = aws_rds_cluster.db.engine
  engine_version                  = var.engine_version
  instance_class                  = var.instance_class
  availability_zone               = local.zones[count.index]
  db_subnet_group_name            = aws_db_subnet_group.db.name
  publicly_accessible             = false
  auto_minor_version_upgrade      = false
  performance_insights_enabled    = true
  performance_insights_kms_key_id = aws_kms_key.db.arn
}
resource "aws_db_event_subscription" "cluster" {
  name        = "${var.name}-cluster"
  sns_topic   = var.site.alarm_topic
  source_type = "db-cluster"
  source_ids  = [aws_rds_cluster.db.id]
}
output "ready_global_id" {
  value      = aws_rds_cluster.db.global_cluster_identifier
  depends_on = [aws_rds_cluster_instance.db]
}
output "resource_id" { value = aws_rds_cluster.db.cluster_resource_id }
output "writer_endpoint" { value = aws_rds_cluster.db.endpoint }
output "reader_endpoint" { value = aws_rds_cluster.db.reader_endpoint }
output "cluster_id" { value = aws_rds_cluster.db.cluster_identifier }
output "key_arn" { value = aws_kms_key.db.arn }
