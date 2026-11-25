resource "aws_iam_role" "recovery" {
  name               = "${var.name}-global-recovery"
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Principal = { Service = "ssm.amazonaws.com" }, Action = "sts:AssumeRole", Condition = { StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id }, ArnLike = { "aws:SourceArn" = "arn:${data.aws_partition.current.partition}:ssm:${var.secondary_region}:${data.aws_caller_identity.current.account_id}:automation-execution/*" } } }] })
}
resource "aws_iam_role_policy" "recovery" {
  name = "managed-global-failover"
  role = aws_iam_role.recovery.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [
    { Effect = "Allow", Action = ["rds:FailoverGlobalCluster"], Resource = [aws_rds_global_cluster.this.arn, aws_rds_cluster.primary.arn, aws_rds_cluster.secondary.arn] },
    { Effect = "Allow", Action = ["rds:DescribeGlobalClusters", "rds:DescribeDBClusters"], Resource = "*" }
  ] })
}
resource "aws_ssm_document" "regional_recovery" {
  provider        = aws.secondary
  name            = "${var.name}-promote-secondary"
  document_type   = "Automation"
  document_format = "JSON"
  content = jsonencode({
    schemaVersion = "0.3"
    description   = "Operator-authorized managed Aurora global failover to the original secondary. Review replication lag and fence application writes before starting. Potential data loss; this does not move EKS traffic."
    assumeRole    = aws_iam_role.recovery.arn
    parameters = {
      DataLossApproval = {
        type          = "String"
        description   = "Required explicit incident commander authorization; review README.md first."
        allowedValues = ["I-approve-potential-data-loss"]
      }
    }
    mainSteps = [
      {
        name           = "PromoteSecondary"
        action         = "aws:executeAwsApi"
        timeoutSeconds = 120
        onFailure      = "Abort"
        inputs = {
          Service                   = "rds"
          Api                       = "FailoverGlobalCluster"
          GlobalClusterIdentifier   = aws_rds_global_cluster.this.id
          TargetDbClusterIdentifier = aws_rds_cluster.secondary.arn
          AllowDataLoss             = true
        }
      },
      {
        name           = "WaitForWriter"
        action         = "aws:waitForAwsResourceProperty"
        timeoutSeconds = 900
        onFailure      = "Abort"
        inputs = {
          Service                 = "rds"
          Api                     = "DescribeGlobalClusters"
          GlobalClusterIdentifier = aws_rds_global_cluster.this.id
          PropertySelector        = "$.GlobalClusters[0].GlobalClusterMembers[?(@.IsWriter == true)].DBClusterArn"
          DesiredValues           = [aws_rds_cluster.secondary.arn]
        }
      },
      {
        name           = "WaitForCluster"
        action         = "aws:waitForAwsResourceProperty"
        timeoutSeconds = 900
        onFailure      = "Abort"
        inputs = {
          Service             = "rds"
          Api                 = "DescribeDBClusters"
          DBClusterIdentifier = aws_rds_cluster.secondary.id
          PropertySelector    = "$.DBClusters[0].Status"
          DesiredValues       = ["available"]
        }
      },
      {
        name   = "ConnectionDetails"
        action = "aws:executeAwsApi"
        isEnd  = true
        inputs = {
          Service             = "rds"
          Api                 = "DescribeDBClusters"
          DBClusterIdentifier = aws_rds_cluster.secondary.id
        }
        outputs = [{ Name = "WriterEndpoint", Selector = "$.DBClusters[0].Endpoint", Type = "String" }]
      }
    ]
    outputs = ["ConnectionDetails.WriterEndpoint"]
  })
  depends_on = [aws_iam_role_policy.recovery]
}
output "recovery_automation" {
  description = "Run in the SECONDARY region using an authorized incident role with ssm:StartAutomationExecution and iam:PassRole for this role."
  value       = { document_name = aws_ssm_document.regional_recovery.name, region = var.secondary_region, execution_role_arn = aws_iam_role.recovery.arn }
}
