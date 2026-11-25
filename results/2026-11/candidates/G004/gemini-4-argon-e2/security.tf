# ------------------------------------------------------------------------------
# KMS Customer Managed Keys (Primary & Secondary Regions)
# ------------------------------------------------------------------------------

data "aws_iam_policy_document" "kms_primary" {
  statement {
    sid    = "EnableIAMUserPermissions"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"]
    }

    actions   = ["kms:*"]
    resources = ["*"]
  }

  statement {
    sid    = "AllowCloudWatchLogsEncryption"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["logs.${var.primary_region}.amazonaws.com"]
    }

    actions = [
      "kms:Encrypt*",
      "kms:Decrypt*",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:Describe*"
    ]

    resources = ["*"]

    condition {
      test     = "ArnLike"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values   = ["arn:${data.aws_partition.current.partition}:logs:${var.primary_region}:${data.aws_caller_identity.current.account_id}:log-group:*"]
    }
  }

  statement {
    sid    = "AllowRDSAndSecretsManager"
    effect = "Allow"

    principals {
      type = "Service"
      identifiers = [
        "rds.amazonaws.com",
        "secretsmanager.amazonaws.com"
      ]
    }

    actions = [
      "kms:Encrypt*",
      "kms:Decrypt*",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:CreateGrant",
      "kms:ListGrants",
      "kms:DescribeKey"
    ]

    resources = ["*"]
  }
}

resource "aws_kms_key" "primary" {
  description             = "KMS key for ${var.service_name} (${local.env_short}) Aurora PostgreSQL in ${var.primary_region}"
  deletion_window_in_days = var.kms_deletion_window_in_days
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.kms_primary.json

  tags = {
    Name   = "${local.primary_cluster_id}-kms"
    Region = var.primary_region
  }
}

resource "aws_kms_alias" "primary" {
  name          = "alias/aurora/${local.primary_cluster_id}"
  target_key_id = aws_kms_key.primary.key_id
}

data "aws_iam_policy_document" "kms_secondary" {
  statement {
    sid    = "EnableIAMUserPermissions"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"]
    }

    actions   = ["kms:*"]
    resources = ["*"]
  }

  statement {
    sid    = "AllowCloudWatchLogsEncryption"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["logs.${var.secondary_region}.amazonaws.com"]
    }

    actions = [
      "kms:Encrypt*",
      "kms:Decrypt*",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:Describe*"
    ]

    resources = ["*"]

    condition {
      test     = "ArnLike"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values   = ["arn:${data.aws_partition.current.partition}:logs:${var.secondary_region}:${data.aws_caller_identity.current.account_id}:log-group:*"]
    }
  }

  statement {
    sid    = "AllowRDSAndSecretsManager"
    effect = "Allow"

    principals {
      type = "Service"
      identifiers = [
        "rds.amazonaws.com",
        "secretsmanager.amazonaws.com"
      ]
    }

    actions = [
      "kms:Encrypt*",
      "kms:Decrypt*",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:CreateGrant",
      "kms:ListGrants",
      "kms:DescribeKey"
    ]

    resources = ["*"]
  }
}

resource "aws_kms_key" "secondary" {
  provider = aws.secondary

  description             = "KMS key for ${var.service_name} (${local.env_short}) Aurora PostgreSQL in ${var.secondary_region}"
  deletion_window_in_days = var.kms_deletion_window_in_days
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.kms_secondary.json

  tags = {
    Name   = "${local.secondary_cluster_id}-kms"
    Region = var.secondary_region
  }
}

resource "aws_kms_alias" "secondary" {
  provider = aws.secondary

  name          = "alias/aurora/${local.secondary_cluster_id}"
  target_key_id = aws_kms_key.secondary.key_id
}

# ------------------------------------------------------------------------------
# Security Groups (Primary & Secondary Regions)
# ------------------------------------------------------------------------------

locals {
  primary_ingress_cidrs = distinct(concat(
    var.allow_vpc_cidr_ingress ? [data.aws_vpc.primary.cidr_block] : [],
    var.allowed_cidr_blocks_primary
  ))

  secondary_ingress_cidrs = distinct(concat(
    var.allow_vpc_cidr_ingress ? [data.aws_vpc.secondary.cidr_block] : [],
    var.allowed_cidr_blocks_secondary
  ))
}

resource "aws_security_group" "primary" {
  name        = "${local.primary_cluster_id}-db-sg"
  description = "Aurora PostgreSQL security group for ${var.service_name} (${local.env_short}) in ${var.primary_region}"
  vpc_id      = data.aws_vpc.primary.id

  tags = {
    Name   = "${local.primary_cluster_id}-db-sg"
    Region = var.primary_region
  }
}

resource "aws_vpc_security_group_ingress_rule" "primary_cidr" {
  for_each = toset(local.primary_ingress_cidrs)

  security_group_id = aws_security_group.primary.id
  description       = "Allow PostgreSQL TCP traffic from ${each.value}"
  ip_protocol       = "tcp"
  from_port         = var.port
  to_port           = var.port
  cidr_ipv4         = each.value

  tags = {
    Name = "${local.primary_cluster_id}-ingress-${replace(each.value, "/", "-")}"
  }
}

resource "aws_vpc_security_group_ingress_rule" "primary_sg" {
  for_each = toset(var.allowed_security_group_ids_primary)

  security_group_id            = aws_security_group.primary.id
  description                  = "Allow PostgreSQL TCP traffic from security group ${each.value}"
  ip_protocol                  = "tcp"
  from_port                    = var.port
  to_port                      = var.port
  referenced_security_group_id = each.value

  tags = {
    Name = "${local.primary_cluster_id}-ingress-${each.value}"
  }
}

resource "aws_vpc_security_group_egress_rule" "primary_intra_vpc" {
  security_group_id = aws_security_group.primary.id
  description       = "Allow outbound traffic within the primary VPC"
  ip_protocol       = "-1"
  cidr_ipv4         = data.aws_vpc.primary.cidr_block

  tags = {
    Name = "${local.primary_cluster_id}-egress-vpc"
  }
}

resource "aws_security_group" "secondary" {
  provider = aws.secondary

  name        = "${local.secondary_cluster_id}-db-sg"
  description = "Aurora PostgreSQL security group for ${var.service_name} (${local.env_short}) in ${var.secondary_region}"
  vpc_id      = data.aws_vpc.secondary.id

  tags = {
    Name   = "${local.secondary_cluster_id}-db-sg"
    Region = var.secondary_region
  }
}

resource "aws_vpc_security_group_ingress_rule" "secondary_cidr" {
  provider = aws.secondary
  for_each = toset(local.secondary_ingress_cidrs)

  security_group_id = aws_security_group.secondary.id
  description       = "Allow PostgreSQL TCP traffic from ${each.value}"
  ip_protocol       = "tcp"
  from_port         = var.port
  to_port           = var.port
  cidr_ipv4         = each.value

  tags = {
    Name = "${local.secondary_cluster_id}-ingress-${replace(each.value, "/", "-")}"
  }
}

resource "aws_vpc_security_group_ingress_rule" "secondary_sg" {
  provider = aws.secondary
  for_each = toset(var.allowed_security_group_ids_secondary)

  security_group_id            = aws_security_group.secondary.id
  description                  = "Allow PostgreSQL TCP traffic from security group ${each.value}"
  ip_protocol                  = "tcp"
  from_port                    = var.port
  to_port                      = var.port
  referenced_security_group_id = each.value

  tags = {
    Name = "${local.secondary_cluster_id}-ingress-${each.value}"
  }
}

resource "aws_vpc_security_group_egress_rule" "secondary_intra_vpc" {
  provider = aws.secondary

  security_group_id = aws_security_group.secondary.id
  description       = "Allow outbound traffic within the secondary VPC"
  ip_protocol       = "-1"
  cidr_ipv4         = data.aws_vpc.secondary.cidr_block

  tags = {
    Name = "${local.secondary_cluster_id}-egress-vpc"
  }
}

# ------------------------------------------------------------------------------
# IAM Role for RDS Enhanced Monitoring
# ------------------------------------------------------------------------------

data "aws_iam_policy_document" "rds_enhanced_monitoring_assume" {
  statement {
    sid     = "AllowRDSMonitoringAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["monitoring.rds.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_iam_role" "rds_enhanced_monitoring" {
  count = var.monitoring_interval > 0 ? 1 : 0

  name               = "${local.name_prefix}-rds-monitoring-role"
  description        = "IAM role allowing RDS Enhanced Monitoring for ${var.service_name} (${local.env_short}) Aurora clusters"
  assume_role_policy = data.aws_iam_policy_document.rds_enhanced_monitoring_assume.json

  tags = {
    Name = "${local.name_prefix}-rds-monitoring-role"
  }
}

resource "aws_iam_role_policy_attachment" "rds_enhanced_monitoring" {
  count = var.monitoring_interval > 0 ? 1 : 0

  role       = aws_iam_role.rds_enhanced_monitoring[0].name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# ------------------------------------------------------------------------------
# IAM Policies for EKS Services (IAM DB Auth & Master Secret Read)
# ------------------------------------------------------------------------------

data "aws_iam_policy_document" "eks_iam_db_connect" {
  statement {
    sid    = "AllowAuroraIAMDatabaseAuthBothRegions"
    effect = "Allow"

    actions = [
      "rds-db:connect"
    ]

    resources = [
      "arn:${data.aws_partition.current.partition}:rds-db:${var.primary_region}:${data.aws_caller_identity.current.account_id}:dbuser:${aws_rds_cluster.primary.cluster_resource_id}/${local.iam_database_user}",
      "arn:${data.aws_partition.current.partition}:rds-db:${var.secondary_region}:${data.aws_caller_identity.current.account_id}:dbuser:${aws_rds_cluster.secondary.cluster_resource_id}/${local.iam_database_user}"
    ]
  }
}

resource "aws_iam_policy" "eks_iam_db_connect" {
  name        = "${local.name_prefix}-aurora-iam-connect"
  description = "Allows EKS service IAM roles for ${var.service_name} (${local.env_short}) to authenticate via IAM to primary and secondary Aurora PostgreSQL clusters"
  policy      = data.aws_iam_policy_document.eks_iam_db_connect.json

  tags = {
    Name = "${local.name_prefix}-aurora-iam-connect"
  }
}

resource "aws_iam_role_policy_attachment" "eks_service_db_connect" {
  for_each = var.service_iam_role_names

  role       = each.value
  policy_arn = aws_iam_policy.eks_iam_db_connect.arn
}

data "aws_iam_policy_document" "master_secret_read" {
  statement {
    sid    = "AllowReadMasterUserSecret"
    effect = "Allow"

    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret"
    ]

    resources = [
      aws_rds_cluster.primary.master_user_secret[0].secret_arn
    ]
  }

  statement {
    sid    = "AllowDecryptMasterUserSecretKMS"
    effect = "Allow"

    actions = [
      "kms:Decrypt"
    ]

    resources = [
      aws_kms_key.primary.arn
    ]

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["secretsmanager.${var.primary_region}.amazonaws.com"]
    }
  }
}

resource "aws_iam_policy" "master_secret_read" {
  name        = "${local.name_prefix}-aurora-master-secret-read"
  description = "Allows reading the RDS-managed master user secret in Secrets Manager for ${var.service_name} (${local.env_short})"
  policy      = data.aws_iam_policy_document.master_secret_read.json

  tags = {
    Name = "${local.name_prefix}-aurora-master-secret-read"
  }
}
