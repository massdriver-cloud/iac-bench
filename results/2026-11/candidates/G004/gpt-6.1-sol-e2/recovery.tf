# Deliberately operator-triggered: a metric alone must not authorize losing committed writes.
# Execute in the surviving region after incident command approves unplanned failover.
resource "aws_iam_role" "recovery" {
  name = "${local.prefix}-recovery"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow", Action = "sts:AssumeRole", Principal = { Service = "ssm.amazonaws.com" }
      Condition = {
        StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id }
        ArnLike      = { "aws:SourceArn" = "arn:${data.aws_partition.current.partition}:ssm:${var.secondary_region}:${data.aws_caller_identity.current.account_id}:automation-execution/*" }
      }
    }]
  })
}
resource "aws_iam_role_policy" "recovery" {
  name = "managed-global-failover"
  role = aws_iam_role.recovery.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow", Action = ["rds:FailoverGlobalCluster"]
        Resource = [aws_rds_global_cluster.this.arn, aws_rds_cluster.primary.arn, aws_rds_cluster.secondary.arn]
      },
      { Effect = "Allow", Action = ["rds:DescribeGlobalClusters"], Resource = "*" }
    ]
  })
}
resource "aws_ssm_document" "regional_recovery" {
  provider        = aws.secondary
  name            = "${local.prefix}-promote-secondary"
  document_type   = "Automation"
  document_format = "JSON"
  content = jsonencode({
    schemaVersion = "0.3"
    description   = "DESTRUCTIVE DR: managed Global Database failover to the pre-provisioned secondary; may lose unreplicated writes. See README before invoking."
    assumeRole    = aws_iam_role.recovery.arn
    mainSteps = [
      {
        name = "PromoteSecondary", action = "aws:executeAwsApi", timeoutSeconds = 120, onFailure = "Abort"
        inputs = {
          Service                   = "rds", Api = "FailoverGlobalCluster"
          GlobalClusterIdentifier   = aws_rds_global_cluster.this.id
          TargetDbClusterIdentifier = aws_rds_cluster.secondary.arn
          AllowDataLoss             = true
        }
      },
      {
        name = "WaitForWriter", action = "aws:waitForAwsResourceProperty", timeoutSeconds = 600, onFailure = "Abort", isEnd = true
        inputs = {
          Service                 = "rds", Api = "DescribeGlobalClusters"
          GlobalClusterIdentifier = aws_rds_global_cluster.this.id
          PropertySelector        = "$.GlobalClusters[0].GlobalClusterMembers[?(@.IsWriter == true)].DBClusterArn"
          DesiredValues           = [aws_rds_cluster.secondary.arn]
        }
      }
    ]
  })
  depends_on = [aws_iam_role_policy.recovery]
}
output "recovery_automation" {
  description = "Operator-triggered, data-loss-authorized failover document in the secondary region. Caller needs ssm:StartAutomationExecution and iam:PassRole for this role."
  value = {
    document = aws_ssm_document.regional_recovery.name
    region   = var.secondary_region
    role_arn = aws_iam_role.recovery.arn
  }
}
