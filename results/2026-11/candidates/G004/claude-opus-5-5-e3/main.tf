locals {
  name          = "${var.service_name}-${var.environment}"
  vpc_name      = "apps-${var.environment}"
  database_name = coalesce(var.database_name, replace(var.service_name, "-", "_"))
  iam_db_user   = coalesce(var.iam_db_username, replace(var.service_name, "-", "_"))
  engine        = "aurora-postgresql"
  family        = "aurora-postgresql${split(".", var.engine_version)[0]}"
  port          = 5432

  primary_cluster_id   = "${local.name}-${var.primary_region}"
  secondary_cluster_id = "${local.name}-${var.secondary_region}"

  common_tags = merge(var.tags, {
    Service            = var.service_name
    Environment        = var.environment
    ManagedBy          = "opentofu"
    DataClassification = "customer-payment"
  })

  cluster_parameters = [
    { name = "rds.force_ssl", value = "1", apply_method = "pending-reboot" },
    { name = "ssl_min_protocol_version", value = "TLSv1.2", apply_method = "pending-reboot" },
    { name = "log_connections", value = "1", apply_method = "immediate" },
    { name = "log_disconnections", value = "1", apply_method = "immediate" },
    { name = "log_min_duration_statement", value = "1000", apply_method = "immediate" },
    { name = "log_lock_waits", value = "1", apply_method = "immediate" },
    { name = "log_statement", value = "ddl", apply_method = "immediate" },
  ]
}

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

# ---------------------------------------------------------------------------
# Network lookups (VPCs and subnets are owned by the network team)
# ---------------------------------------------------------------------------

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
  tags = { tier = "database" }
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
  tags = { tier = "database" }
}

# ---------------------------------------------------------------------------
# Encryption keys (customer-managed, one per region)
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "kms" {
  for_each = toset([var.primary_region, var.secondary_region])

  statement {
    sid       = "AccountAdministration"
    actions   = ["kms:*"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }

  statement {
    sid = "CloudWatchLogs"
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
      identifiers = ["logs.${each.key}.amazonaws.com"]
    }
    condition {
      test     = "ArnLike"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values   = ["arn:${data.aws_partition.current.partition}:logs:${each.key}:${data.aws_caller_identity.current.account_id}:log-group:/aws/rds/cluster/${local.name}-*"]
    }
  }
}

resource "aws_kms_key" "primary" {
  description             = "Aurora ${local.name} encryption key (${var.primary_region})"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  policy                  = data.aws_iam_policy_document.kms[var.primary_region].json
}

resource "aws_kms_alias" "primary" {
  name          = "alias/aurora/${local.name}"
  target_key_id = aws_kms_key.primary.key_id
}

resource "aws_kms_key" "secondary" {
  provider                = aws.secondary
  description             = "Aurora ${local.name} encryption key (${var.secondary_region})"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  policy                  = data.aws_iam_policy_document.kms[var.secondary_region].json
}

resource "aws_kms_alias" "secondary" {
  provider      = aws.secondary
  name          = "alias/aurora/${local.name}"
  target_key_id = aws_kms_key.secondary.key_id
}

# ---------------------------------------------------------------------------
# Master credentials (break-glass only; apps use IAM auth)
# ---------------------------------------------------------------------------

resource "random_password" "master" {
  length           = 40
  special          = true
  override_special = "!#$%^&*()-_=+[]{}<>:?"
}

resource "aws_secretsmanager_secret" "master" {
  name                    = "aurora/${local.name}/master"
  description             = "Master credentials for Aurora global database ${local.name}"
  kms_key_id              = aws_kms_key.primary.arn
  recovery_window_in_days = 30

  # Replicated so credentials remain available if the primary region is down.
  replica {
    region     = var.secondary_region
    kms_key_id = aws_kms_key.secondary.arn
  }
}

resource "aws_secretsmanager_secret_version" "master" {
  secret_id = aws_secretsmanager_secret.master.id
  secret_string = jsonencode({
    engine   = "postgres"
    username = var.master_username
    password = random_password.master.result
    host     = aws_rds_global_cluster.this.endpoint
    port     = local.port
    dbname   = local.database_name
  })
}

# ---------------------------------------------------------------------------
# Enhanced monitoring role (IAM is global)
# ---------------------------------------------------------------------------

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
  name               = "${local.name}-aurora-monitoring"
  assume_role_policy = data.aws_iam_policy_document.monitoring_assume.json
}

resource "aws_iam_role_policy_attachment" "monitoring" {
  role       = aws_iam_role.monitoring.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# ---------------------------------------------------------------------------
# Global cluster
# ---------------------------------------------------------------------------

resource "aws_rds_global_cluster" "this" {
  global_cluster_identifier = local.name
  engine                    = local.engine
  engine_version            = var.engine_version
  database_name             = local.database_name
  storage_encrypted         = true
  deletion_protection       = var.deletion_protection

  lifecycle {
    precondition {
      condition     = var.primary_region != var.secondary_region
      error_message = "primary_region and secondary_region must be different regions."
    }
  }
}
