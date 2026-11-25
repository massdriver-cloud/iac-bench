output "global_database" {
  description = "Global identity and AWS-managed writer endpoint. For IAM clients, discover the current regional writer and sign a token for its region/hostname as described in RUNBOOK.md."
  value = {
    identifier      = aws_rds_global_cluster.this.id
    arn             = aws_rds_global_cluster.this.arn
    writer_endpoint = aws_rds_global_cluster.this.endpoint
    port            = 5432
    database_name   = var.database_name
  }
}
output "regional_clusters" {
  description = "Regional endpoints and ARNs. Primary/secondary describe initial deployment only; query AWS for the current writer after failover."
  value = {
    primary = {
      region          = var.primary_region
      arn             = aws_rds_cluster.primary.arn
      identifier      = aws_rds_cluster.primary.id
      endpoint        = aws_rds_cluster.primary.endpoint
      reader_endpoint = aws_rds_cluster.primary.reader_endpoint
      resource_id     = aws_rds_cluster.primary.cluster_resource_id
    }
    secondary = {
      region          = var.secondary_region
      arn             = aws_rds_cluster.secondary.arn
      identifier      = aws_rds_cluster.secondary.id
      endpoint        = aws_rds_cluster.secondary.endpoint
      reader_endpoint = aws_rds_cluster.secondary.reader_endpoint
      resource_id     = aws_rds_cluster.secondary.cluster_resource_id
    }
  }
}
output "bootstrap_secret_arn" {
  description = "Break-glass credential; no app role receives permission to read it. Replicated to the recovery region under that region's KMS key."
  value       = aws_secretsmanager_secret.bootstrap.arn
}
output "application_connect_policy_arn" {
  value       = aws_iam_policy.connect.arn
  description = "Policy attached to supplied application roles; does not create SQL users."
}
output "alarm_topic_arns" {
  value = {
    primary   = aws_sns_topic.primary.arn
    secondary = aws_sns_topic.secondary.arn
  }
  description = "Confirm regional email subscriptions and add production paging integrations."
}
