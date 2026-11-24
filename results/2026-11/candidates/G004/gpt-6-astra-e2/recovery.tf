data "aws_iam_policy_document" "recovery_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ssm.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:${data.aws_partition.current.partition}:ssm:${var.secondary_region}:${data.aws_caller_identity.current.account_id}:automation-execution/*"]
    }
  }
}
resource "aws_iam_role" "recovery" {
  name_prefix        = "${local.name}-recovery-"
  assume_role_policy = data.aws_iam_policy_document.recovery_assume.json
}
resource "aws_iam_role_policy" "recovery" {
  role = aws_iam_role.recovery.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["rds:FailoverGlobalCluster"]
        Resource = [aws_rds_global_cluster.this.arn, aws_rds_cluster.primary.arn, aws_rds_cluster.secondary.arn]
      },
      {
        Effect   = "Allow"
        Action   = ["rds:DescribeGlobalClusters"]
        Resource = "*"
      }
    ]
  })
}

resource "aws_ssm_document" "recover" {
  provider        = aws.secondary
  name            = "${local.name}-promote-recovery-region"
  document_type   = "Automation"
  document_format = "JSON"
  content = jsonencode({
    schemaVersion = "0.3"
    description   = "Emergency initial-primary to initial-secondary Aurora managed failover. Requires incident commander approval and fencing application writes. Allows data loss. Does NOT reroute EKS traffic."
    assumeRole    = aws_iam_role.recovery.arn
    parameters = {
      Acknowledgement = {
        type          = "String"
        description   = "Confirm source-region application writes are fenced, lag/data-loss risk reviewed, and incident commander has authorized failover."
        allowedValues = ["FENCED_AND_ACCEPT_DATA_LOSS"]
      }
    }
    mainSteps = [{
      name           = "PromoteRecoveryRegion"
      action         = "aws:executeScript"
      timeoutSeconds = 600
      isEnd          = true
      inputs = {
        Runtime = "python3.11"
        Handler = "recover"
        InputPayload = {
          region          = var.secondary_region
          global          = aws_rds_global_cluster.this.id
          target          = aws_rds_cluster.secondary.arn
          acknowledgement = "{{ Acknowledgement }}"
        }
        Script = <<-PY
          import boto3
          import time

          def recover(event, context):
              if event['acknowledgement'] != 'FENCED_AND_ACCEPT_DATA_LOSS':
                  raise RuntimeError('Explicit incident authorization required')
              client = boto3.client('rds', region_name=event['region'])
              def describe():
                  return client.describe_global_clusters(GlobalClusterIdentifier=event['global'])['GlobalClusters'][0]
              def target_is_writer(cluster):
                  return any(m['DBClusterArn'] == event['target'] and m['IsWriter'] for m in cluster['GlobalClusterMembers'])
              cluster = describe()
              if target_is_writer(cluster) and cluster['Status'] == 'available':
                  return {'status': 'already-promoted', 'writer': event['target']}
              if cluster['Status'] != 'available':
                  raise RuntimeError('Global cluster is busy; inspect current operation before retrying')
              if not any(m['DBClusterArn'] == event['target'] for m in cluster['GlobalClusterMembers']):
                  raise RuntimeError('Recovery cluster is not a global member')
              client.failover_global_cluster(
                  GlobalClusterIdentifier=event['global'],
                  TargetDbClusterIdentifier=event['target'],
                  AllowDataLoss=True)
              deadline = time.monotonic() + 540
              while time.monotonic() < deadline:
                  cluster = describe()
                  if target_is_writer(cluster) and cluster['Status'] == 'available':
                      return {'status': 'promoted', 'writer': event['target'],
                              'next': 'Verify SQL writes and route service traffic to recovery EKS region'}
                  time.sleep(10)
              raise RuntimeError('Timed out observing promotion; operation may still be running. Inspect RDS before retrying.')
        PY
      }
    }]
  })
  depends_on = [aws_iam_role_policy.recovery]
}

output "recovery_automation" {
  value = {
    document_name = aws_ssm_document.recover.name
    region        = var.secondary_region
    role_arn      = aws_iam_role.recovery.arn
  }
}
