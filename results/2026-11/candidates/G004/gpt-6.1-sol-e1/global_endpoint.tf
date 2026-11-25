output "global_writer_endpoint" {
  description = "AWS-managed writer DNS follows managed global failover. For IAM connections use writer discovery to obtain the regional endpoint and token-signing region; see discover-writer.py."
  value       = aws_rds_global_cluster.this.endpoint
}
output "writer_discovery_policy_json" {
  description = "Attach alongside application_iam_policy_json only if the workload uses runtime writer discovery. Read-only metadata APIs require wildcard resource access."
  value = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["rds:DescribeGlobalClusters", "rds:DescribeDBClusters"]
      Resource = "*"
    }]
  })
}
