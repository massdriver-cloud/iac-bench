# Recovery is deliberately operator-triggered, not a blind response to a missing metric.
# This control path lives in the recovery region and uses managed global failover,
# never detach/promote (which risks split brain and strands the global topology).
resource "aws_iam_role" "recovery" {
  name = "${local.prefix}-recovery"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow", Action = "sts:AssumeRole",
      Principal = { Service = "ssm.amazonaws.com" },
      Condition = {
        StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id }
        ArnLike      = { "aws:SourceArn" = "arn:${data.aws_partition.current.partition}:ssm:${var.secondary_region}:${data.aws_caller_identity.current.account_id}:automation-execution/*" }
      }
    }]
  })
}
resource "aws_iam_role_policy" "recovery" {
  role = aws_iam_role.recovery.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow", Action = ["rds:FailoverGlobalCluster"],
        Resource = [aws_rds_global_cluster.database.arn, aws_rds_cluster.primary.arn, aws_rds_cluster.secondary.arn]
      },
      {
        Effect = "Allow", Action = ["rds:DescribeGlobalClusters", "rds:DescribeDBClusters"], Resource = "*"
      }
    ]
  })
}
resource "aws_ssm_document" "recover" {
  provider        = aws.secondary
  name            = "${local.prefix}-recover-database"
  document_type   = "Automation"
  document_format = "JSON"
  content = jsonencode({
    schemaVersion = "0.3"
    description   = "Managed Aurora Global Database failover to the original recovery region. Requires explicit acknowledgement of potential asynchronous write loss. Check external service probes and recent RPO lag first."
    assumeRole    = aws_iam_role.recovery.arn
    parameters = {
      ConfirmDataLoss = {
        type          = "String"
        description   = "Incident commander approval: asynchronous replication can lose unreplicated writes."
        allowedValues = ["I_ACCEPT_POSSIBLE_DATA_LOSS"]
      }
    }
    mainSteps = [{
      name           = "ManagedGlobalFailover"
      action         = "aws:executeScript"
      timeoutSeconds = 600
      isEnd          = true
      inputs = {
        Runtime = "python3.11"
        Handler = "recover"
        InputPayload = {
          confirmation = "{{ ConfirmDataLoss }}"
          region       = var.secondary_region
          global_id    = aws_rds_global_cluster.database.id
          target_arn   = aws_rds_cluster.secondary.arn
          target_id    = aws_rds_cluster.secondary.id
        }
        Script = <<-PY
          import time
          import boto3
          from botocore.config import Config

          def recover(event, context):
              if event['confirmation'] != 'I_ACCEPT_POSSIBLE_DATA_LOSS':
                  raise ValueError('Explicit incident-commander approval is required')
              rds = boto3.client('rds', region_name=event['region'], config=Config(
                  connect_timeout=5, read_timeout=20, retries={'max_attempts': 3, 'mode': 'standard'}))
              def describe():
                  return rds.describe_global_clusters(GlobalClusterIdentifier=event['global_id'])['GlobalClusters'][0]
              def target_is_writer(global_db):
                  return any(m['DBClusterArn'] == event['target_arn'] and m['IsWriter']
                             for m in global_db['GlobalClusterMembers'])
              global_db = describe()
              if not any(m['DBClusterArn'] == event['target_arn'] for m in global_db['GlobalClusterMembers']):
                  raise RuntimeError('Recovery cluster is not a global member; do not detach or promote manually')
              if not target_is_writer(global_db):
                  if global_db['Status'] == 'available':
                      rds.failover_global_cluster(GlobalClusterIdentifier=event['global_id'],
                          TargetDbClusterIdentifier=event['target_arn'], AllowDataLoss=True)
                  elif global_db['Status'] != 'failing-over':
                      raise RuntimeError('Global cluster is not ready: ' + global_db['Status'])
              deadline = time.monotonic() + 480
              while time.monotonic() < deadline:
                  global_db = describe()
                  cluster = rds.describe_db_clusters(DBClusterIdentifier=event['target_id'])['DBClusters'][0]
                  if (target_is_writer(global_db) and global_db['Status'] == 'available'
                          and cluster['Status'] == 'available'
                          and any(i['IsClusterWriter'] for i in cluster['DBClusterMembers'])):
                      return {'writer_endpoint': cluster['Endpoint'], 'region': event['region'],
                              'next_step': 'Test TLS/IAM login and write/read probe before routing production traffic'}
                  time.sleep(10)
              raise RuntimeError('Failover not confirmed within eight minutes. Inspect AWS operation; do not initiate a competing promotion.')
        PY
      }
    }]
  })
  depends_on = [aws_iam_role_policy.recovery, aws_rds_cluster_instance.secondary]
}

output "recovery_automation" {
  description = "Start this SSM Automation in the recovery region with explicit data-loss acknowledgement. No automatic regional failover is implied."
  value = {
    region        = var.secondary_region
    document_name = aws_ssm_document.recover.name
    role_arn      = aws_iam_role.recovery.arn
    parameters    = { ConfirmDataLoss = ["I_ACCEPT_POSSIBLE_DATA_LOSS"] }
  }
}
