################################################################################
# Aurora PostgreSQL Global Database (Cross-Region Sub-Second RPO / Sub-Minute RTO)
################################################################################

resource "aws_rds_global_cluster" "this" {
  provider = aws.primary

  global_cluster_identifier = local.global_cluster_id
  engine                    = "aurora-postgresql"
  engine_version            = local.engine_version
  database_name             = var.database_name
  storage_encrypted         = true
  deletion_protection       = var.deletion_protection
  force_destroy             = false

  lifecycle {
    precondition {
      condition     = var.primary_region != var.secondary_region
      error_message = "primary_region and secondary_region must be distinct AWS regions."
    }

    precondition {
      condition     = data.aws_rds_engine_version.primary.supports_global_databases && data.aws_rds_engine_version.secondary.supports_global_databases
      error_message = "Aurora PostgreSQL ${var.engine_version} does not support Aurora Global Databases in both configured regions."
    }
  }
}

################################################################################
# Pre-Created KMS-Encrypted CloudWatch Log Groups (Both Regions)
# Created before the clusters so Aurora writes audit and IAM auth logs into
# CMK-encrypted log groups with PCI-compliant retention instead of auto-creating
# unencrypted, never-expiring log groups.
################################################################################

resource "aws_cloudwatch_log_group" "primary" {
  provider = aws.primary
  for_each = toset(local.cloudwatch_log_exports)

  name              = "/aws/rds/cluster/${local.primary_cluster_id}/${each.value}"
  retention_in_days = var.log_retention_days
  kms_key_id        = aws_kms_key.primary.arn

  tags = {
    Name = "${local.primary_cluster_id}-${each.value}-logs"
  }
}

resource "aws_cloudwatch_log_group" "secondary" {
  provider = aws.secondary
  for_each = toset(local.cloudwatch_log_exports)

  name              = "/aws/rds/cluster/${local.secondary_cluster_id}/${each.value}"
  retention_in_days = var.log_retention_days
  kms_key_id        = aws_kms_key.secondary.arn

  tags = {
    Name = "${local.secondary_cluster_id}-${each.value}-logs"
  }
}
