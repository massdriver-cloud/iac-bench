terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

variable "name" { type = string }
variable "environment" { type = string }
variable "is_primary" { type = bool }
variable "global_cluster_identifier" { type = string }
variable "engine" { type = string }
variable "engine_version" { type = string }
variable "database_name" { type = string }
variable "master_username" { type = string }
variable "master_password" {
  type      = string
  sensitive = true
  default   = null
}
variable "instance_class" { type = string }
variable "instance_count" { type = number }
variable "backup_retention_days" { type = number }
variable "preferred_backup_window" { type = string }
variable "preferred_maintenance_window" { type = string }
variable "allowed_security_group_ids" { type = list(string) }
variable "allowed_cidr_blocks" { type = list(string) }
variable "monitoring_role_arn" { type = string }
variable "skip_final_snapshot" { type = bool }
variable "replication_lag_threshold_ms" {
  type    = number
  default = 5000
}
variable "alarm_actions" {
  type    = list(string)
  default = []
}
variable "wait_for" {
  description = "Opaque values the cluster must wait for (e.g. primary writer IDs, IAM policy attachment IDs)."
  type        = list(string)
  default     = []
}

data "aws_region" "this" {}
data "aws_caller_identity" "this" {}

# ---------------------------------------------------------------------------
# Network: VPC and database subnets owned by the network team.
# ---------------------------------------------------------------------------
data "aws_vpc" "this" {
  filter {
    name   = "tag:Name"
    values = ["apps-${var.environment}"]
  }
}

data "aws_subnets" "database" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.this.id]
  }

  tags = {
    tier = "database"
  }
}

locals {
  region       = data.aws_region.this.region
  default_cidr = length(var.allowed_security_group_ids) == 0 && length(var.allowed_cidr_blocks) == 0
  ingress_cidr = local.default_cidr ? [data.aws_vpc.this.cidr_block] : var.allowed_cidr_blocks
  family       = "aurora-postgresql${split(".", var.engine_version)[0]}"
}

resource "aws_db_subnet_group" "this" {
  name        = "${var.name}-${local.region}"
  description = "Database subnets (tier=database) in apps-${var.environment} for ${var.name}"
  subnet_ids  = data.aws_subnets.database.ids

  lifecycle {
    precondition {
      condition     = length(data.aws_subnets.database.ids) >= 2
      error_message = "At least two subnets tagged tier=database (in different AZs) are required in apps-${var.environment}."
    }
  }
}

resource "aws_security_group" "this" {
  name_prefix = "${var.name}-aurora-"
  description = "Aurora PostgreSQL access for ${var.name}"
  vpc_id      = data.aws_vpc.this.id

  tags = {
    Name = "${var.name}-aurora"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "sg" {
  for_each = toset(var.allowed_security_group_ids)

  security_group_id            = aws_security_group.this.id
  description                  = "PostgreSQL from ${each.value}"
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  referenced_security_group_id = each.value
}

resource "aws_vpc_security_group_ingress_rule" "cidr" {
  for_each = toset(local.ingress_cidr)

  security_group_id = aws_security_group.this.id
  description       = "PostgreSQL from ${each.value}"
  ip_protocol       = "tcp"
  from_port         = 5432
  to_port           = 5432
  cidr_ipv4         = each.value
}

# ---------------------------------------------------------------------------
# Encryption: customer-managed key per region (global database secondaries
# must be encrypted with a key in their own region).
# ---------------------------------------------------------------------------
resource "aws_kms_key" "this" {
  description             = "Aurora storage, Performance Insights and secrets for ${var.name} (${local.region})"
  enable_key_rotation     = true
  deletion_window_in_days = 30
}

resource "aws_kms_alias" "this" {
  name          = "alias/${var.name}-aurora"
  target_key_id = aws_kms_key.this.key_id
}

# ---------------------------------------------------------------------------
# Parameter groups
# ---------------------------------------------------------------------------
resource "aws_rds_cluster_parameter_group" "this" {
  name_prefix = "${var.name}-cluster-"
  family      = local.family
  description = "Cluster parameters for ${var.name}"

  # Customer and payment data: reject any unencrypted connection.
  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }

  parameter {
    name  = "ssl_min_protocol_version"
    value = "TLSv1.2"
  }

  parameter {
    name  = "log_connections"
    value = "1"
  }

  parameter {
    name  = "log_disconnections"
    value = "1"
  }

  parameter {
    name  = "log_min_duration_statement"
    value = "1000"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_db_parameter_group" "this" {
  name_prefix = "${var.name}-instance-"
  family      = local.family
  description = "Instance parameters for ${var.name}"

  lifecycle {
    create_before_destroy = true
  }
}

# ---------------------------------------------------------------------------
# Cluster
# ---------------------------------------------------------------------------
resource "terraform_data" "wait_for" {
  input = var.wait_for
}

resource "aws_rds_cluster" "this" {
  cluster_identifier        = "${var.name}-${local.region}"
  global_cluster_identifier = var.global_cluster_identifier
  engine                    = var.engine
  engine_version            = var.engine_version
  engine_mode               = "provisioned"

  # Only the primary carries credentials/database name; the secondary
  # inherits them through storage-level replication.
  database_name   = var.is_primary ? var.database_name : null
  master_username = var.is_primary ? var.master_username : null
  master_password = var.is_primary ? var.master_password : null

  db_subnet_group_name            = aws_db_subnet_group.this.name
  vpc_security_group_ids          = [aws_security_group.this.id]
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.this.name
  port                            = 5432

  storage_encrypted = true
  kms_key_id        = aws_kms_key.this.arn

  # Applications authenticate with their IAM roles, not passwords.
  iam_database_authentication_enabled = true

  backup_retention_period      = var.backup_retention_days
  preferred_backup_window      = var.preferred_backup_window
  preferred_maintenance_window = var.preferred_maintenance_window
  copy_tags_to_snapshot        = true
  deletion_protection          = true
  skip_final_snapshot          = var.skip_final_snapshot
  final_snapshot_identifier    = "${var.name}-${local.region}-final"

  enabled_cloudwatch_logs_exports = ["postgresql"]

  depends_on = [terraform_data.wait_for]

  lifecycle {
    # After a managed switchover/failover the roles of the two clusters swap;
    # engine upgrades are driven through the global cluster.
    ignore_changes = [
      replication_source_identifier,
      global_cluster_identifier,
      engine_version,
      master_password,
      database_name,
      master_username,
    ]
  }
}

resource "aws_rds_cluster_instance" "this" {
  count = var.instance_count

  identifier              = "${var.name}-${local.region}-${count.index + 1}"
  cluster_identifier      = aws_rds_cluster.this.id
  engine                  = aws_rds_cluster.this.engine
  engine_version          = aws_rds_cluster.this.engine_version
  instance_class          = var.instance_class
  db_subnet_group_name    = aws_db_subnet_group.this.name
  db_parameter_group_name = aws_db_parameter_group.this.name
  publicly_accessible     = false
  promotion_tier          = count.index
  copy_tags_to_snapshot   = true

  # Global databases require matching engine versions across regions;
  # upgrades are coordinated through the global cluster.
  auto_minor_version_upgrade = false

  monitoring_interval = 30
  monitoring_role_arn = var.monitoring_role_arn

  performance_insights_enabled          = true
  performance_insights_kms_key_id       = aws_kms_key.this.arn
  performance_insights_retention_period = 7

  preferred_maintenance_window = var.preferred_maintenance_window

  lifecycle {
    ignore_changes = [engine_version]
  }
}

# ---------------------------------------------------------------------------
# Replication lag alarm: the business tolerates only seconds of data loss on
# a regional failure, so lag above the threshold must page someone. The
# metric is only emitted by a secondary cluster; the alarm is created in both
# regions so it keeps working after the roles swap.
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "replication_lag" {
  alarm_name          = "${var.name}-${local.region}-global-replication-lag"
  alarm_description   = "Aurora global database replication lag into ${local.region} exceeds ${var.replication_lag_threshold_ms} ms (RPO at risk)."
  namespace           = "AWS/RDS"
  metric_name         = "AuroraGlobalDBReplicationLag"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 3
  datapoints_to_alarm = 2
  threshold           = var.replication_lag_threshold_ms
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = var.alarm_actions
  ok_actions          = var.alarm_actions

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.this.cluster_identifier
  }
}

# ---------------------------------------------------------------------------
# Outputs
# ---------------------------------------------------------------------------
output "cluster_arn" { value = aws_rds_cluster.this.arn }
output "cluster_identifier" { value = aws_rds_cluster.this.cluster_identifier }
output "cluster_resource_id" { value = aws_rds_cluster.this.cluster_resource_id }
output "writer_endpoint" { value = aws_rds_cluster.this.endpoint }
output "reader_endpoint" { value = aws_rds_cluster.this.reader_endpoint }
output "instance_ids" { value = aws_rds_cluster_instance.this[*].id }
output "security_group_id" { value = aws_security_group.this.id }
output "kms_key_arn" { value = aws_kms_key.this.arn }
output "region" { value = local.region }
output "account_id" { value = data.aws_caller_identity.this.account_id }
