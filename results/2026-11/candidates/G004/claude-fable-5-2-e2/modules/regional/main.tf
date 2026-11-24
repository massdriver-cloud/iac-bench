# Everything a cluster needs in one region. Instantiated once per region with
# identical inputs so the two regions cannot drift apart - after a failover the
# standby region must behave exactly like the region it replaces.

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.80.0, < 7.0.0"
    }
  }
}

###############################################################################
# Plan-time sanity check
###############################################################################

# Fails the plan (rather than an apply 20 minutes in) if this region does not
# offer the requested engine version and instance class for global databases.
data "aws_rds_orderable_db_instance" "this" {
  engine                     = var.engine
  engine_version             = var.engine_version
  preferred_instance_classes = [var.instance_class]
  supports_global_databases  = true
}

###############################################################################
# Network: the network team's VPC and its database subnets
###############################################################################

data "aws_vpc" "this" {
  filter {
    name   = "tag:Name"
    values = [var.vpc_name]
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

data "aws_subnet" "database" {
  for_each = toset(data.aws_subnets.database.ids)
  id       = each.value
}

resource "aws_db_subnet_group" "this" {
  name        = var.name
  description = "Private database subnets of ${var.vpc_name} for ${var.name}"
  subnet_ids  = data.aws_subnets.database.ids

  tags = {
    Name = var.name
  }

  lifecycle {
    precondition {
      condition     = length(distinct([for s in data.aws_subnet.database : s.availability_zone])) >= 2
      error_message = "VPC ${var.vpc_name} in ${var.region} needs subnets tagged tier=database in at least two availability zones."
    }
  }
}

resource "aws_security_group" "this" {
  name        = "${var.name}-aurora"
  description = "Aurora PostgreSQL ${var.name}: inbound only from approved client security groups"
  vpc_id      = data.aws_vpc.this.id

  # No egress rules: the database never initiates connections.

  tags = {
    Name = "${var.name}-aurora"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "clients" {
  for_each = toset(var.client_security_group_ids)

  security_group_id            = aws_security_group.this.id
  referenced_security_group_id = each.value
  ip_protocol                  = "tcp"
  from_port                    = var.port
  to_port                      = var.port
  description                  = "PostgreSQL from ${each.value}"
}

###############################################################################
# Encryption: a customer-managed key per region
###############################################################################

data "aws_iam_policy_document" "kms" {
  statement {
    sid       = "AccountAdministration"
    actions   = ["kms:*"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["arn:${var.partition}:iam::${var.account_id}:root"]
    }
  }

  statement {
    sid = "DatabaseLogEncryption"
    actions = [
      "kms:Encrypt*",
      "kms:Decrypt*",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:Describe*",
    ]
    resources = ["*"]

    principals {
      type        = "Service"
      identifiers = ["logs.${var.region}.amazonaws.com"]
    }

    condition {
      test     = "ArnLike"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values   = ["arn:${var.partition}:logs:${var.region}:${var.account_id}:log-group:/aws/rds/cluster/${var.cluster_identifier}/*"]
    }
  }
}

resource "aws_kms_key" "this" {
  description             = "Aurora ${var.name} in ${var.region}: storage, backups, logs, Performance Insights and credentials"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  policy                  = data.aws_iam_policy_document.kms.json
}

resource "aws_kms_alias" "this" {
  name          = "alias/${var.name}-aurora"
  target_key_id = aws_kms_key.this.key_id
}

###############################################################################
# Engine configuration and logs
###############################################################################

resource "aws_rds_cluster_parameter_group" "this" {
  name        = "${var.name}-${var.parameter_group_family}"
  family      = var.parameter_group_family
  description = "Cluster parameters for ${var.name}"

  dynamic "parameter" {
    for_each = var.cluster_parameters

    content {
      name         = parameter.value.name
      value        = parameter.value.value
      apply_method = parameter.value.apply_method
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_cloudwatch_log_group" "postgresql" {
  name              = "/aws/rds/cluster/${var.cluster_identifier}/postgresql"
  retention_in_days = var.log_retention_days
  kms_key_id        = aws_kms_key.this.arn
}

###############################################################################
# Replication-lag alarm
###############################################################################

# Only the cluster currently acting as standby reports this metric, so the
# alarm exists in both regions and sits in INSUFFICIENT_DATA on whichever
# cluster is currently the writer. That keeps alerting intact after the roles
# swap in a switchover or failover.
resource "aws_cloudwatch_metric_alarm" "replication_lag" {
  alarm_name          = "${var.cluster_identifier}-global-replication-lag"
  alarm_description   = "Cross-region replication into ${var.cluster_identifier} is more than ${var.replication_lag_alarm_seconds}s behind the writer. Writes made in that gap would be lost if the writer region failed now."
  namespace           = "AWS/RDS"
  metric_name         = "AuroraGlobalDBReplicationLag"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 3
  datapoints_to_alarm = 3
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.replication_lag_alarm_seconds * 1000 # metric is in milliseconds
  treat_missing_data  = "missing"
  alarm_actions       = var.alarm_sns_topic_arns
  ok_actions          = var.alarm_sns_topic_arns

  dimensions = {
    DBClusterIdentifier = var.cluster_identifier
  }
}
