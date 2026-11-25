output "global_cluster_id" {
  description = "Aurora Global Database identifier."
  value       = aws_rds_global_cluster.this.id
}

output "primary" {
  description = "Primary (writable) regional cluster details."
  value = {
    region              = module.primary.region
    cluster_id          = module.primary.cluster_id
    writer_endpoint     = module.primary.writer_endpoint
    reader_endpoint     = module.primary.reader_endpoint
    port                = module.primary.port
    master_user_secret  = module.primary.master_user_secret_arn
    kms_key_arn         = module.primary.kms_key_arn
    security_group_id   = module.primary.security_group_id
    cluster_resource_id = module.primary.cluster_resource_id
  }
}

output "secondary" {
  description = "Secondary (read-only until promoted) regional cluster details."
  value = {
    region              = module.secondary.region
    cluster_id          = module.secondary.cluster_id
    writer_endpoint     = module.secondary.writer_endpoint
    reader_endpoint     = module.secondary.reader_endpoint
    port                = module.secondary.port
    kms_key_arn         = module.secondary.kms_key_arn
    security_group_id   = module.secondary.security_group_id
    cluster_resource_id = module.secondary.cluster_resource_id
  }
}

output "app_connect_policy_arn" {
  description = "IAM policy granting rds-db:connect for app_db_users on both regional clusters. Null when app_db_users is empty."
  value       = try(aws_iam_policy.app_connect[0].arn, null)
}

output "replication_lag_alarm_name" {
  description = "CloudWatch alarm (in the secondary region) that fires when replication lag exceeds the RPO budget."
  value       = module.secondary.replication_lag_alarm_name
}

output "failover_runbook" {
  description = "What to do when the primary region is lost."
  value       = <<-EOT
    Regional failover (primary ${var.primary_region} unavailable, secondary ${var.secondary_region} serving):

    1. Confirm the outage is regional and the secondary is healthy:
         aws rds describe-global-clusters --global-cluster-identifier ${aws_rds_global_cluster.this.id}
       Check AuroraGlobalDBReplicationLag in ${var.secondary_region} to estimate lost writes (the RPO).

    2. Detach the secondary and promote it to a standalone writable cluster:
         aws rds remove-from-global-cluster --global-cluster-identifier ${aws_rds_global_cluster.this.id} --db-cluster-identifier ${module.secondary.cluster_arn}
         aws rds promote-read-replica-db-cluster --db-cluster-identifier ${module.secondary.cluster_id}

    3. Point services at the promoted cluster's writer endpoint: ${module.secondary.writer_endpoint}
       (Services should use the endpoint name from configuration, so this is a config change, not a code change.)

    4. When ${var.primary_region} recovers, do not re-attach the old primary. Rebuild a new secondary
       from the promoted cluster with a fresh aws_rds_global_cluster in code, then fail back on a planned window.

    Note: Aurora Global Database does not fail over automatically. This runbook is manual, so
    the RTO target is set by how quickly the on-call engineer executes it.
  EOT
}
