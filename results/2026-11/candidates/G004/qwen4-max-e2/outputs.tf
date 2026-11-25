output "global_cluster_identifier" {
  description = "Aurora Global Database identifier (use with aws rds switchover-global-cluster / failover-global-cluster)."
  value       = aws_rds_global_cluster.this.global_cluster_identifier
}

output "primary" {
  description = "Primary-region connection and resource details."
  value = {
    region                 = var.primary_region
    cluster_id             = aws_rds_cluster.primary.cluster_identifier
    cluster_arn            = aws_rds_cluster.primary.arn
    writer_endpoint        = aws_rds_cluster.primary.endpoint
    reader_endpoint        = aws_rds_cluster.primary.reader_endpoint
    port                   = aws_rds_cluster.primary.port
    database_name          = local.database_name
    master_secret_arn      = try(aws_rds_cluster.primary.master_user_secret[0].secret_arn, null)
    kms_key_arn            = aws_kms_key.primary.arn
    security_group_id      = aws_security_group.primary.id
    rds_connect_policy_arn = aws_iam_policy.rds_connect_primary.arn
    alerts_topic_arn       = aws_sns_topic.alerts_primary.arn
  }
}

output "secondary" {
  description = "Secondary-region (DR) connection and resource details. Reader endpoint serves reads until the region is promoted."
  value = {
    region          = var.secondary_region
    cluster_id      = aws_rds_cluster.secondary.cluster_identifier
    cluster_arn     = aws_rds_cluster.secondary.arn
    reader_endpoint = aws_rds_cluster.secondary.reader_endpoint
    # Resolves to the writer once this region is promoted.
    writer_endpoint        = aws_rds_cluster.secondary.endpoint
    port                   = aws_rds_cluster.secondary.port
    kms_key_arn            = aws_kms_key.secondary.arn
    security_group_id      = aws_security_group.secondary.id
    rds_connect_policy_arn = aws_iam_policy.rds_connect_secondary.arn
    alerts_topic_arn       = aws_sns_topic.alerts_secondary.arn
  }
}

output "failover_runbook" {
  description = "One-line reminder of the DR procedure; full runbook in README.md."
  value       = "Planned: aws rds switchover-global-cluster --global-cluster-identifier ${aws_rds_global_cluster.this.global_cluster_identifier} --target-db-cluster-identifier ${aws_rds_cluster.secondary.arn} --region ${var.secondary_region}. Regional outage: aws rds failover-global-cluster (see README.md)."
}
